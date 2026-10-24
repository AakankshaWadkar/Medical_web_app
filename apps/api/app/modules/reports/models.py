import uuid
from datetime import date
from decimal import Decimal

from sqlalchemy import BigInteger, Date, Integer, Numeric, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.models import Base


class MRPerformanceSummary(Base):
    __tablename__ = "view_mr_performance_summary"
    __table_args__ = {"info": {"is_view": True}}

    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    mr_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    report_month: Mapped[date] = mapped_column(Date, primary_key=True)
    mr_name: Mapped[str] = mapped_column(String)
    total_visits: Mapped[int] = mapped_column(BigInteger)
    doctor_visits: Mapped[int] = mapped_column(BigInteger)
    chemist_visits: Mapped[int] = mapped_column(BigInteger)
    stockist_visits: Mapped[int] = mapped_column(BigInteger)
    total_pob_booked: Mapped[Decimal] = mapped_column(Numeric(14, 2))


class DoctorCoverageMetric(Base):
    __tablename__ = "view_doctor_coverage_metrics"
    __table_args__ = {"info": {"is_view": True}}

    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    doctor_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    coverage_month: Mapped[date | None] = mapped_column(Date, primary_key=True)
    doctor_code: Mapped[str] = mapped_column(String)
    doctor_name: Mapped[str] = mapped_column(String)
    category_name: Mapped[str] = mapped_column(String)
    target_frequency: Mapped[int] = mapped_column(Integer)
    visits_completed: Mapped[int] = mapped_column(BigInteger)
    coverage_status: Mapped[str] = mapped_column(String)


class SecondarySalesAggregate(Base):
    __tablename__ = "view_secondary_sales_aggregates"
    __table_args__ = {"info": {"is_view": True}}

    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    stockist_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    product_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    reporting_month: Mapped[int] = mapped_column(Integer, primary_key=True)
    reporting_year: Mapped[int] = mapped_column(Integer, primary_key=True)
    stockist_name: Mapped[str] = mapped_column(String)
    product_name: Mapped[str] = mapped_column(String)
    total_quantity_sold: Mapped[int] = mapped_column(BigInteger)
    total_free_quantity: Mapped[int] = mapped_column(BigInteger)
    total_secondary_sales_value: Mapped[Decimal] = mapped_column(Numeric(14, 2))
