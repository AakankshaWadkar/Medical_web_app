import argparse
import asyncio
import json
import sys
import uuid

from sqlalchemy import text

from app.core.db import platform_session


async def create_tenant(
    name: str,
    slug: str,
    admin_email: str,
    admin_name: str,
    admin_password: str,
    company_code: str | None = None,
    currency: str = "INR",
    branch_code: str = "HQ-MAIN",
    branch_name: str = "Corporate Head Office",
) -> dict:
    code = company_code or slug.replace("-", "").upper()[:8]
    tenant_id = uuid.uuid4()
    branch_id = uuid.uuid4()
    auth_user_id = uuid.uuid4()
    app_user_id = uuid.uuid4()
    audit_id = uuid.uuid4()

    async with platform_session() as session:
        # Check if slug exists
        existing_tenant = await session.execute(
            text("select id from public.tenants where slug = :slug"),
            {"slug": slug},
        )
        if existing_tenant.scalar_one_or_none():
            raise ValueError(f"Tenant with slug '{slug}' already exists")

        # Check if admin email exists
        existing_user = await session.execute(
            text("select id from auth.users where email = :email"),
            {"email": admin_email},
        )
        if existing_user.scalar_one_or_none():
            raise ValueError(f"Auth user with email '{admin_email}' already exists")

        # 1. Insert Tenant
        await session.execute(
            text("""
                insert into public.tenants (id, name, slug, company_code, status, currency, created_at, updated_at)
                values (:id, :name, :slug, :code, 'active', :currency, now(), now())
            """),
            {
                "id": tenant_id,
                "name": name,
                "slug": slug,
                "code": code,
                "currency": currency,
            },
        )

        # 2. Insert Default Head Office Branch
        await session.execute(
            text("""
                insert into public.branches (id, tenant_id, code, name, is_head_office, created_at, updated_at, version)
                values (:id, :tenant_id, :code, :name, true, now(), now(), 1)
            """),
            {
                "id": branch_id,
                "tenant_id": tenant_id,
                "code": branch_code,
                "name": branch_name,
            },
        )

        # 3. Insert Supabase auth.users
        await session.execute(
            text("""
                insert into auth.users (
                    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                    confirmation_token, recovery_token, email_change_token_new, email_change,
                    email_change_token_current, phone_change, phone_change_token, reauthentication_token
                )
                values (
                    :id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
                    :email, crypt(cast(:password as text), gen_salt('bf')), now(),
                    cast('{"provider":"email","providers":["email"]}' as jsonb),
                    cast(json_build_object('full_name', cast(:admin_name as text)) as jsonb),
                    now(), now(),
                    '', '', '', '', '', '', '', ''
                )
            """),
            {
                "id": auth_user_id,
                "email": admin_email,
                "password": admin_password,
                "admin_name": admin_name,
            },
        )

        # 4. Insert auth.identities
        await session.execute(
            text("""
                insert into auth.identities (
                    id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at
                )
                values (
                    gen_random_uuid(), :user_id,
                    cast(json_build_object('sub', cast(:user_id_str as text), 'email', cast(:email as text)) as jsonb),
                    'email', cast(:user_id_str as text), now(), now(), now()
                )
            """),
            {
                "user_id": auth_user_id,
                "user_id_str": str(auth_user_id),
                "email": admin_email,
            },
        )

        # 5. Insert public.app_users
        await session.execute(
            text("""
                insert into public.app_users (
                    id, tenant_id, auth_user_id, app_role, full_name, branch_id, status, created_at, updated_at, version
                )
                values (
                    :id, :tenant_id, :auth_user_id, 'admin', :full_name, :branch_id, 'active', now(), now(), 1
                )
            """),
            {
                "id": app_user_id,
                "tenant_id": tenant_id,
                "auth_user_id": auth_user_id,
                "full_name": admin_name,
                "branch_id": branch_id,
            },
        )

        # 6. Insert audit_logs
        await session.execute(
            text("""
                insert into public.audit_logs (
                    id, tenant_id, user_id, entity_name, entity_id, action, new_values, created_at, updated_at, version
                )
                values (
                    :id, :tenant_id, :user_id, 'tenants', :entity_id, 'insert',
                    cast(json_build_object('name', cast(:name as text), 'slug', cast(:slug as text), 'admin_email', cast(:admin_email as text)) as jsonb),
                    now(), now(), 1
                )
            """),
            {
                "id": audit_id,
                "tenant_id": tenant_id,
                "user_id": app_user_id,
                "entity_id": tenant_id,
                "name": name,
                "slug": slug,
                "admin_email": admin_email,
            },
        )

    return {
        "status": "success",
        "tenant_id": str(tenant_id),
        "slug": slug,
        "name": name,
        "branch_id": str(branch_id),
        "admin_auth_user_id": str(auth_user_id),
        "admin_app_user_id": str(app_user_id),
        "admin_email": admin_email,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="PharmaSphere Platform CLI")
    subparsers = parser.add_subparsers(dest="command", required=True)

    create_parser = subparsers.add_parser("create-tenant", help="Bootstrap a new tenant company")
    create_parser.add_argument("--name", required=True, help="Company Name")
    create_parser.add_argument("--slug", required=True, help="Unique Tenant Slug")
    create_parser.add_argument("--admin-email", required=True, help="First Admin Email")
    create_parser.add_argument("--admin-name", required=True, help="First Admin Full Name")
    create_parser.add_argument("--admin-password", required=True, help="First Admin Password")
    create_parser.add_argument("--company-code", required=False, help="Short Company Code")
    create_parser.add_argument(
        "--currency", required=False, default="INR", help="Default Currency (INR)"
    )
    create_parser.add_argument(
        "--branch-code", required=False, default="HQ-MAIN", help="Head Office Branch Code"
    )
    create_parser.add_argument(
        "--branch-name",
        required=False,
        default="Corporate Head Office",
        help="Head Office Branch Name",
    )

    args = parser.parse_args()

    if args.command == "create-tenant":
        try:
            result = asyncio.run(
                create_tenant(
                    name=args.name,
                    slug=args.slug,
                    admin_email=args.admin_email,
                    admin_name=args.admin_name,
                    admin_password=args.admin_password,
                    company_code=args.company_code,
                    currency=args.currency,
                    branch_code=args.branch_code,
                    branch_name=args.branch_name,
                )
            )
            print(json.dumps(result, indent=2))
        except Exception as e:
            print(f"Error creating tenant: {e}", file=sys.stderr)
            sys.exit(1)


if __name__ == "__main__":
    main()
