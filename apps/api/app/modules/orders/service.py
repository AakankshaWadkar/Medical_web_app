import uuid
from datetime import date
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.auth import Principal
from app.core.errors import BadRequestError, ConflictError, ForbiddenError, NotFoundError
from app.core.pagination import PaginatedResponse, PaginationParams, paginate
from app.modules.masters.models import Product
from app.modules.masters.service import MastersService
from app.modules.orders.models import (
    PrimaryOrder,
    PrimaryOrderItem,
    SecondarySale,
    SecondarySaleItem,
)
from app.modules.orders.schemas import (
    PrimaryOrderCreate,
    PrimaryOrderItemResponse,
    PrimaryOrderResponse,
    PrimaryOrderStatusUpdate,
    SecondarySaleCreate,
    SecondarySaleItemResponse,
    SecondarySaleResponse,
)
from app.modules.users.models import AppUser

VALID_PRIMARY_ORDER_TRANSITIONS: dict[str, set[str]] = {
    "draft": {"submitted", "cancelled"},
    "submitted": {"approved", "cancelled"},
    "approved": {"processing", "cancelled"},
    "processing": {"dispatched", "cancelled"},
    "dispatched": set(),
    "cancelled": set(),
}


class OrdersService:
    @staticmethod
    async def get_app_user(db: AsyncSession, principal: Principal) -> AppUser:
        return await MastersService.get_app_user(db, principal)

    # -------------------------------------------------------------------------
    # Primary Orders
    # -------------------------------------------------------------------------
    @staticmethod
    async def create_primary_order(
        db: AsyncSession, principal: Principal, data: PrimaryOrderCreate
    ) -> PrimaryOrderResponse:
        order_date = data.order_date or date.today()
        order_number = (
            data.order_number
            or f"PO-{int(date.today().strftime('%Y%m%d'))}-{uuid.uuid4().hex[:6].upper()}"
        )

        # Check unique order number
        existing_order = await db.execute(
            select(PrimaryOrder.id).where(
                PrimaryOrder.tenant_id == principal.tenant_id,
                PrimaryOrder.order_number == order_number,
                PrimaryOrder.deleted_at.is_(None),
            )
        )
        if existing_order.scalar_one_or_none():
            raise ConflictError(f"Primary order with number '{order_number}' already exists")

        total_subtotal = Decimal("0.00")
        total_tax = Decimal("0.00")
        items: list[PrimaryOrderItem] = []

        for item_data in data.items:
            prod_res = await db.execute(
                select(Product).where(
                    Product.id == item_data.product_id,
                    Product.tenant_id == principal.tenant_id,
                    Product.deleted_at.is_(None),
                )
            )
            product = prod_res.scalar_one_or_none()
            if not product:
                raise NotFoundError(f"Product {item_data.product_id} not found")
            if not product.is_active:
                raise ConflictError(f"Product '{product.name}' is inactive")

            unit_price = (
                item_data.unit_price
                if item_data.unit_price is not None
                else (product.pts if product.pts > 0 else product.ptr)
            )
            discount_mult = Decimal("1.00") - (item_data.discount_percent / Decimal("100.00"))
            discounted_unit = (unit_price * discount_mult).quantize(Decimal("0.01"))
            line_subtotal = (discounted_unit * Decimal(item_data.ordered_quantity)).quantize(
                Decimal("0.01")
            )
            line_tax = (line_subtotal * (item_data.tax_percent / Decimal("100.00"))).quantize(
                Decimal("0.01")
            )
            line_total = line_subtotal + line_tax

            item = PrimaryOrderItem(
                tenant_id=principal.tenant_id,
                product_id=product.id,
                ordered_quantity=item_data.ordered_quantity,
                unit_price=unit_price,
                discount_percent=item_data.discount_percent,
                tax_amount=line_tax,
                line_total=line_total,
            )
            items.append(item)
            total_subtotal += line_subtotal
            total_tax += line_tax

        order = PrimaryOrder(
            tenant_id=principal.tenant_id,
            order_number=order_number,
            stockist_id=data.stockist_id,
            division_id=data.division_id,
            order_date=order_date,
            status="draft",
            subtotal=total_subtotal,
            tax_amount=total_tax,
            total_amount=total_subtotal + total_tax,
        )
        order.items = items
        db.add(order)
        await db.flush()

        # Reload with items
        order_res = await db.execute(
            select(PrimaryOrder)
            .options(selectinload(PrimaryOrder.items))
            .where(PrimaryOrder.id == order.id)
        )
        saved_order = order_res.scalar_one()
        return PrimaryOrderResponse(
            id=saved_order.id,
            tenant_id=saved_order.tenant_id,
            order_number=saved_order.order_number,
            stockist_id=saved_order.stockist_id,
            division_id=saved_order.division_id,
            order_date=saved_order.order_date,
            status=saved_order.status,
            subtotal=saved_order.subtotal,
            tax_amount=saved_order.tax_amount,
            total_amount=saved_order.total_amount,
            items=[PrimaryOrderItemResponse.model_validate(it) for it in saved_order.items],
            created_at=saved_order.created_at,
            updated_at=saved_order.updated_at,
        )

    @staticmethod
    async def update_primary_order_status(
        db: AsyncSession, principal: Principal, order_id: uuid.UUID, data: PrimaryOrderStatusUpdate
    ) -> PrimaryOrderResponse:
        app_user = await OrdersService.get_app_user(db, principal)

        result = await db.execute(
            select(PrimaryOrder)
            .options(selectinload(PrimaryOrder.items))
            .where(
                PrimaryOrder.id == order_id,
                PrimaryOrder.tenant_id == principal.tenant_id,
                PrimaryOrder.deleted_at.is_(None),
            )
        )
        order = result.scalar_one_or_none()
        if not order:
            raise NotFoundError("Primary order not found")

        current_status = order.status
        target_status = data.status

        # 1. State machine validation
        allowed_targets = VALID_PRIMARY_ORDER_TRANSITIONS.get(current_status, set())
        if target_status not in allowed_targets:
            raise BadRequestError(
                f"Invalid order status transition from '{current_status}' to '{target_status}'. Allowed: {sorted(list(allowed_targets))}"
            )

        # 2. Role validation for transitions (e.g. approval requires Manager or Admin)
        if target_status in {"approved", "processing", "dispatched"} and app_user.app_role not in {
            "admin",
            "manager",
        }:
            raise ForbiddenError(
                f"Role '{app_user.app_role}' is not authorized to set order status to '{target_status}'"
            )

        order.status = target_status
        await db.flush()
        await db.refresh(order)

        return PrimaryOrderResponse(
            id=order.id,
            tenant_id=order.tenant_id,
            order_number=order.order_number,
            stockist_id=order.stockist_id,
            division_id=order.division_id,
            order_date=order.order_date,
            status=order.status,
            subtotal=order.subtotal,
            tax_amount=order.tax_amount,
            total_amount=order.total_amount,
            items=[PrimaryOrderItemResponse.model_validate(it) for it in order.items],
            created_at=order.created_at,
            updated_at=order.updated_at,
        )

    @staticmethod
    async def list_primary_orders(
        db: AsyncSession,
        principal: Principal,
        pagination: PaginationParams,
        stockist_id: uuid.UUID | None = None,
        status: str | None = None,
        from_date: date | None = None,
        to_date: date | None = None,
    ) -> PaginatedResponse[PrimaryOrderResponse]:
        query = select(PrimaryOrder).where(
            PrimaryOrder.tenant_id == principal.tenant_id,
            PrimaryOrder.deleted_at.is_(None),
        )

        if stockist_id:
            query = query.where(PrimaryOrder.stockist_id == stockist_id)
        if status:
            query = query.where(PrimaryOrder.status == status)
        if from_date:
            query = query.where(PrimaryOrder.order_date >= from_date)
        if to_date:
            query = query.where(PrimaryOrder.order_date <= to_date)

        items, total, total_pages = await paginate(
            db,
            query.order_by(PrimaryOrder.order_date.desc(), PrimaryOrder.created_at.desc()),
            pagination,
        )

        responses = [
            PrimaryOrderResponse(
                id=o.id,
                tenant_id=o.tenant_id,
                order_number=o.order_number,
                stockist_id=o.stockist_id,
                division_id=o.division_id,
                order_date=o.order_date,
                status=o.status,
                subtotal=o.subtotal,
                tax_amount=o.tax_amount,
                total_amount=o.total_amount,
                items=[],
                created_at=o.created_at,
                updated_at=o.updated_at,
            )
            for o in items
        ]
        return PaginatedResponse(
            items=responses,
            total=total,
            page=pagination.page,
            page_size=pagination.page_size,
            total_pages=total_pages,
        )

    @staticmethod
    async def get_primary_order(
        db: AsyncSession, principal: Principal, order_id: uuid.UUID
    ) -> PrimaryOrderResponse:
        result = await db.execute(
            select(PrimaryOrder)
            .options(selectinload(PrimaryOrder.items))
            .where(
                PrimaryOrder.id == order_id,
                PrimaryOrder.tenant_id == principal.tenant_id,
                PrimaryOrder.deleted_at.is_(None),
            )
        )
        order = result.scalar_one_or_none()
        if not order:
            raise NotFoundError("Primary order not found")

        return PrimaryOrderResponse(
            id=order.id,
            tenant_id=order.tenant_id,
            order_number=order.order_number,
            stockist_id=order.stockist_id,
            division_id=order.division_id,
            order_date=order.order_date,
            status=order.status,
            subtotal=order.subtotal,
            tax_amount=order.tax_amount,
            total_amount=order.total_amount,
            items=[PrimaryOrderItemResponse.model_validate(it) for it in order.items],
            created_at=order.created_at,
            updated_at=order.updated_at,
        )

    # -------------------------------------------------------------------------
    # Secondary Sales (Chemist orders from stockist)
    # -------------------------------------------------------------------------
    @staticmethod
    async def create_secondary_sale(
        db: AsyncSession, principal: Principal, data: SecondarySaleCreate
    ) -> SecondarySaleResponse:
        sale_date = data.sale_date or date.today()
        reporting_month = data.reporting_month or sale_date.month
        reporting_year = data.reporting_year or sale_date.year

        total_value = Decimal("0.00")
        items: list[SecondarySaleItem] = []

        for item_data in data.items:
            prod_res = await db.execute(
                select(Product).where(
                    Product.id == item_data.product_id,
                    Product.tenant_id == principal.tenant_id,
                    Product.deleted_at.is_(None),
                )
            )
            product = prod_res.scalar_one_or_none()
            if not product:
                raise NotFoundError(f"Product {item_data.product_id} not found")
            if not product.is_active:
                raise ConflictError(f"Product '{product.name}' is inactive")

            rate = item_data.rate if item_data.rate is not None else product.ptr
            item_total = (rate * Decimal(item_data.quantity)).quantize(Decimal("0.01"))

            item = SecondarySaleItem(
                tenant_id=principal.tenant_id,
                product_id=product.id,
                batch_id=item_data.batch_id,
                quantity=item_data.quantity,
                free_quantity=item_data.free_quantity,
                rate=rate,
                total_amount=item_total,
            )
            items.append(item)
            total_value += item_total

        sale = SecondarySale(
            tenant_id=principal.tenant_id,
            stockist_id=data.stockist_id,
            chemist_id=data.chemist_id,
            sale_date=sale_date,
            invoice_no=data.invoice_no,
            total_value=total_value,
            reporting_month=reporting_month,
            reporting_year=reporting_year,
        )
        sale.items = items
        db.add(sale)
        await db.flush()

        sale_res = await db.execute(
            select(SecondarySale)
            .options(selectinload(SecondarySale.items))
            .where(SecondarySale.id == sale.id)
        )
        saved_sale = sale_res.scalar_one()
        return SecondarySaleResponse(
            id=saved_sale.id,
            tenant_id=saved_sale.tenant_id,
            stockist_id=saved_sale.stockist_id,
            chemist_id=saved_sale.chemist_id,
            sale_date=saved_sale.sale_date,
            invoice_no=saved_sale.invoice_no,
            total_value=saved_sale.total_value,
            reporting_month=saved_sale.reporting_month,
            reporting_year=saved_sale.reporting_year,
            items=[SecondarySaleItemResponse.model_validate(it) for it in saved_sale.items],
            created_at=saved_sale.created_at,
            updated_at=saved_sale.updated_at,
        )

    @staticmethod
    async def list_secondary_sales(
        db: AsyncSession,
        principal: Principal,
        pagination: PaginationParams,
        stockist_id: uuid.UUID | None = None,
        chemist_id: uuid.UUID | None = None,
        reporting_month: int | None = None,
        reporting_year: int | None = None,
    ) -> PaginatedResponse[SecondarySaleResponse]:
        query = select(SecondarySale).where(
            SecondarySale.tenant_id == principal.tenant_id,
            SecondarySale.deleted_at.is_(None),
        )

        if stockist_id:
            query = query.where(SecondarySale.stockist_id == stockist_id)
        if chemist_id:
            query = query.where(SecondarySale.chemist_id == chemist_id)
        if reporting_month:
            query = query.where(SecondarySale.reporting_month == reporting_month)
        if reporting_year:
            query = query.where(SecondarySale.reporting_year == reporting_year)

        items, total, total_pages = await paginate(
            db,
            query.order_by(SecondarySale.sale_date.desc(), SecondarySale.created_at.desc()),
            pagination,
        )

        responses = [
            SecondarySaleResponse(
                id=s.id,
                tenant_id=s.tenant_id,
                stockist_id=s.stockist_id,
                chemist_id=s.chemist_id,
                sale_date=s.sale_date,
                invoice_no=s.invoice_no,
                total_value=s.total_value,
                reporting_month=s.reporting_month,
                reporting_year=s.reporting_year,
                items=[],
                created_at=s.created_at,
                updated_at=s.updated_at,
            )
            for s in items
        ]
        return PaginatedResponse(
            items=responses,
            total=total,
            page=pagination.page,
            page_size=pagination.page_size,
            total_pages=total_pages,
        )

    @staticmethod
    async def get_secondary_sale(
        db: AsyncSession, principal: Principal, sale_id: uuid.UUID
    ) -> SecondarySaleResponse:
        result = await db.execute(
            select(SecondarySale)
            .options(selectinload(SecondarySale.items))
            .where(
                SecondarySale.id == sale_id,
                SecondarySale.tenant_id == principal.tenant_id,
                SecondarySale.deleted_at.is_(None),
            )
        )
        sale = result.scalar_one_or_none()
        if not sale:
            raise NotFoundError("Secondary sale record not found")

        return SecondarySaleResponse(
            id=sale.id,
            tenant_id=sale.tenant_id,
            stockist_id=sale.stockist_id,
            chemist_id=sale.chemist_id,
            sale_date=sale.sale_date,
            invoice_no=sale.invoice_no,
            total_value=sale.total_value,
            reporting_month=sale.reporting_month,
            reporting_year=sale.reporting_year,
            items=[SecondarySaleItemResponse.model_validate(it) for it in sale.items],
            created_at=sale.created_at,
            updated_at=sale.updated_at,
        )
