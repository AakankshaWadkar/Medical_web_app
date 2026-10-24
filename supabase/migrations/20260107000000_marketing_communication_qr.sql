-- Migration: 20260107000000_marketing_communication_qr.sql
-- Description: Stage (f) Marketing, Communication & QR - Campaigns, Schemes, Offers, Coupons, Promotional Materials, Notifications, Templates, Dispatches, QR Codes
-- Conventions: tenant_id uuid not null, apply_tenant_rls, numeric(14,2), timestamptz, check constraints

--------------------------------------------------------------------------------
-- 1. Campaigns
--------------------------------------------------------------------------------
create table public.campaigns (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  start_date date not null,
  end_date date not null,
  budget numeric(14,2) not null default 0.00 check (budget >= 0),
  status text not null default 'planned' check (status in ('planned', 'active', 'completed', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_campaigns_code unique (tenant_id, code),
  constraint ck_campaigns_dates check (end_date >= start_date)
);

call public.apply_tenant_rls('public.campaigns');

--------------------------------------------------------------------------------
-- 2. Campaign Territories
--------------------------------------------------------------------------------
create table public.campaign_territories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  territory_id uuid not null references public.territories(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_campaign_territories unique (tenant_id, campaign_id, territory_id)
);

call public.apply_tenant_rls('public.campaign_territories');
create index idx_camp_terr_campaign on public.campaign_territories (tenant_id, campaign_id);
create index idx_camp_terr_territory on public.campaign_territories (tenant_id, territory_id);

--------------------------------------------------------------------------------
-- 3. Campaign Products
--------------------------------------------------------------------------------
create table public.campaign_products (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_campaign_products unique (tenant_id, campaign_id, product_id)
);

call public.apply_tenant_rls('public.campaign_products');
create index idx_camp_prod_campaign on public.campaign_products (tenant_id, campaign_id);
create index idx_camp_prod_product on public.campaign_products (tenant_id, product_id);

--------------------------------------------------------------------------------
-- 4. Schemes
--------------------------------------------------------------------------------
create table public.schemes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  scheme_type text not null check (scheme_type in ('product_bonus', 'quantity_discount', 'value_discount')),
  start_date date not null,
  end_date date not null,
  is_active boolean not null default true,
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_schemes_code unique (tenant_id, code),
  constraint ck_schemes_dates check (end_date >= start_date)
);

call public.apply_tenant_rls('public.schemes');

--------------------------------------------------------------------------------
-- 5. Scheme Products
--------------------------------------------------------------------------------
create table public.scheme_products (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  scheme_id uuid not null references public.schemes(id) on delete cascade,
  buy_product_id uuid not null references public.products(id) on delete cascade,
  buy_quantity integer not null check (buy_quantity > 0),
  free_product_id uuid not null references public.products(id) on delete cascade,
  free_quantity integer not null default 0 check (free_quantity >= 0),
  discount_percentage numeric(5,2) not null default 0.00 check (discount_percentage >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.scheme_products');
create index idx_scheme_products_scheme on public.scheme_products (tenant_id, scheme_id);
create index idx_scheme_products_buy on public.scheme_products (tenant_id, buy_product_id);
create index idx_scheme_products_free on public.scheme_products (tenant_id, free_product_id);

--------------------------------------------------------------------------------
-- 6. Scheme Slabs
--------------------------------------------------------------------------------
create table public.scheme_slabs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  scheme_id uuid not null references public.schemes(id) on delete cascade,
  min_order_amount numeric(14,2) not null check (min_order_amount >= 0),
  max_order_amount numeric(14,2) check (max_order_amount is null or max_order_amount >= min_order_amount),
  benefit_type text not null check (benefit_type in ('discount_percent', 'cash_rebate')),
  benefit_value numeric(14,2) not null check (benefit_value > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.scheme_slabs');
create index idx_scheme_slabs_scheme on public.scheme_slabs (tenant_id, scheme_id);

--------------------------------------------------------------------------------
-- 7. Offers
--------------------------------------------------------------------------------
create table public.offers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  title text not null,
  offer_type text not null check (offer_type in ('seasonal', 'clearance', 'introductory')),
  discount_percent numeric(5,2) not null default 0.00 check (discount_percent >= 0),
  max_discount numeric(14,2) not null default 0.00 check (max_discount >= 0),
  valid_from timestamptz not null default now(),
  valid_to timestamptz not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_offers_code unique (tenant_id, code),
  constraint ck_offers_dates check (valid_to >= valid_from)
);

call public.apply_tenant_rls('public.offers');

--------------------------------------------------------------------------------
-- 8. Coupons
--------------------------------------------------------------------------------
create table public.coupons (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  offer_id uuid not null references public.offers(id) on delete cascade,
  coupon_code text not null,
  max_uses integer not null default 1 check (max_uses > 0),
  used_count integer not null default 0 check (used_count >= 0),
  valid_from timestamptz not null default now(),
  valid_to timestamptz not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_coupons_code unique (tenant_id, coupon_code),
  constraint ck_coupons_dates check (valid_to >= valid_from)
);

call public.apply_tenant_rls('public.coupons');
create index idx_coupons_offer on public.coupons (tenant_id, offer_id);

--------------------------------------------------------------------------------
-- 9. Coupon Redemptions
--------------------------------------------------------------------------------
create table public.coupon_redemptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  coupon_id uuid not null references public.coupons(id) on delete cascade,
  customer_type text not null check (customer_type in ('stockist', 'chemist')),
  entity_id uuid not null,
  order_id uuid,
  redeemed_at timestamptz not null default now(),
  discount_amount numeric(14,2) not null default 0.00 check (discount_amount >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.coupon_redemptions');
create index idx_coupon_redemptions_coupon on public.coupon_redemptions (tenant_id, coupon_id);
create index idx_coupon_redemptions_entity on public.coupon_redemptions (tenant_id, customer_type, entity_id);

--------------------------------------------------------------------------------
-- 10. Product Promotions
--------------------------------------------------------------------------------
create table public.product_promotions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  campaign_id uuid references public.campaigns(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  promotion_type text not null check (promotion_type in ('special_price', 'bundled')),
  promotional_price numeric(14,2) not null check (promotional_price >= 0),
  start_date date not null,
  end_date date not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint ck_promotions_dates check (end_date >= start_date)
);

call public.apply_tenant_rls('public.product_promotions');
create index idx_prod_promotions_camp on public.product_promotions (tenant_id, campaign_id);
create index idx_prod_promotions_prod on public.product_promotions (tenant_id, product_id);

--------------------------------------------------------------------------------
-- 11. Promotional Materials
--------------------------------------------------------------------------------
create table public.promotional_materials (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  campaign_id uuid references public.campaigns(id) on delete cascade,
  material_name text not null,
  material_type text not null check (material_type in ('brochure', 'banner', 'booklet', 'digital_asset')),
  file_id uuid references public.file_storage(id) on delete set null,
  unit_cost numeric(14,2) not null default 0.00 check (unit_cost >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.promotional_materials');
create index idx_promo_materials_camp on public.promotional_materials (tenant_id, campaign_id);
create index idx_promo_materials_file on public.promotional_materials (tenant_id, file_id);

--------------------------------------------------------------------------------
-- 12. Promotional Material Distributions
--------------------------------------------------------------------------------
create table public.promotional_material_distributions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  promotional_material_id uuid not null references public.promotional_materials(id) on delete cascade,
  mr_id uuid references public.app_users(id) on delete set null,
  distributed_to_entity_type text not null check (distributed_to_entity_type in ('doctors', 'chemists', 'hospitals')),
  entity_id uuid not null,
  quantity integer not null check (quantity > 0),
  distribution_date date not null default current_date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.promotional_material_distributions');
create index idx_promo_dist_material on public.promotional_material_distributions (tenant_id, promotional_material_id, distribution_date);
create index idx_promo_dist_mr on public.promotional_material_distributions (tenant_id, mr_id);
create index idx_promo_dist_entity on public.promotional_material_distributions (tenant_id, distributed_to_entity_type, entity_id);

--------------------------------------------------------------------------------
-- 13. Notifications
--------------------------------------------------------------------------------
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references public.app_users(id) on delete cascade,
  title text not null,
  message text not null,
  notification_type text not null check (notification_type in ('tour_plan_approved', 'target_achieved', 'visit_reminder', 'system_alert', 'order_placed', 'stock_alert')),
  entity_type text,
  entity_id uuid,
  is_read boolean not null default false,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.notifications');
create index idx_notifications_user_unread on public.notifications (tenant_id, user_id, is_read, created_at desc);

--------------------------------------------------------------------------------
-- 14. Email Templates
--------------------------------------------------------------------------------
create table public.email_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  template_code text not null,
  subject text not null,
  body_html text not null,
  body_text text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_email_templates_code unique (tenant_id, template_code)
);

call public.apply_tenant_rls('public.email_templates');

--------------------------------------------------------------------------------
-- 15. Emails
--------------------------------------------------------------------------------
create table public.emails (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  to_email text not null,
  subject text not null,
  body text not null,
  entity_type text,
  entity_id uuid,
  status text not null default 'queued' check (status in ('queued', 'sent', 'failed')),
  error_message text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.emails');
create index idx_emails_status on public.emails (tenant_id, status, sent_at desc);

--------------------------------------------------------------------------------
-- 16. SMS Templates
--------------------------------------------------------------------------------
create table public.sms_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  template_code text not null,
  sender_id text not null,
  template_text text not null,
  dlt_template_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_sms_templates_code unique (tenant_id, template_code)
);

call public.apply_tenant_rls('public.sms_templates');

--------------------------------------------------------------------------------
-- 17. SMS
--------------------------------------------------------------------------------
create table public.sms (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  recipient_phone text not null,
  message text not null,
  dlt_template_id text,
  entity_type text,
  entity_id uuid,
  status text not null default 'queued' check (status in ('queued', 'sent', 'delivered', 'failed')),
  gateway_response text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.sms');
create index idx_sms_status on public.sms (tenant_id, status, sent_at desc);

--------------------------------------------------------------------------------
-- 18. WhatsApp Templates
--------------------------------------------------------------------------------
create table public.whatsapp_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  template_name text not null,
  category text not null check (category in ('utility', 'marketing')),
  language text not null default 'en',
  header text,
  body text not null,
  footer text,
  buttons jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_whatsapp_templates_name_lang unique (tenant_id, template_name, language)
);

call public.apply_tenant_rls('public.whatsapp_templates');

--------------------------------------------------------------------------------
-- 19. WhatsApp
--------------------------------------------------------------------------------
create table public.whatsapp (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  recipient_phone text not null,
  template_id uuid references public.whatsapp_templates(id) on delete set null,
  payload jsonb,
  entity_type text,
  entity_id uuid,
  status text not null default 'sent' check (status in ('sent', 'delivered', 'read', 'failed')),
  sent_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.whatsapp');
create index idx_whatsapp_status on public.whatsapp (tenant_id, status, sent_at desc);
create index idx_whatsapp_template on public.whatsapp (tenant_id, template_id);

--------------------------------------------------------------------------------
-- 20. Push Notifications
--------------------------------------------------------------------------------
create table public.push_notifications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references public.app_users(id) on delete cascade,
  title text not null,
  body text not null,
  device_token text,
  data_payload jsonb,
  status text not null default 'sent' check (status in ('sent', 'failed')),
  sent_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.push_notifications');
create index idx_push_notifications_user on public.push_notifications (tenant_id, user_id, sent_at desc);

--------------------------------------------------------------------------------
-- 21. Communication Logs
--------------------------------------------------------------------------------
create table public.communication_logs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  channel text not null check (channel in ('email', 'sms', 'whatsapp', 'push')),
  direction text not null check (direction in ('outbound', 'inbound')),
  recipient text not null,
  status text not null,
  payload jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.communication_logs');
create index idx_comm_logs_channel on public.communication_logs (tenant_id, channel, created_at desc);

--------------------------------------------------------------------------------
-- 22. Unified QR Codes
--------------------------------------------------------------------------------
create table public.qr_codes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code_value text not null,
  entity_type text not null check (entity_type in ('product', 'batch', 'doctor', 'chemist', 'equipment')),
  entity_id uuid not null,
  qr_type text not null check (qr_type in ('product_verification', 'master_id', 'promotional')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_qr_codes_value unique (tenant_id, code_value)
);

call public.apply_tenant_rls('public.qr_codes');
create index idx_qr_codes_entity on public.qr_codes (tenant_id, entity_type, entity_id);

--------------------------------------------------------------------------------
-- 23. QR Code Scans
--------------------------------------------------------------------------------
create table public.qr_code_scans (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  qr_code_id uuid not null references public.qr_codes(id) on delete cascade,
  scanned_by_user_id uuid references public.app_users(id) on delete set null,
  scan_time timestamptz not null default now(),
  latitude double precision,
  longitude double precision,
  device_info jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.qr_code_scans');
create index idx_qr_scans_code on public.qr_code_scans (tenant_id, qr_code_id, scan_time desc);
create index idx_qr_scans_user on public.qr_code_scans (tenant_id, scanned_by_user_id);

--------------------------------------------------------------------------------
-- 24. QR Code Histories
--------------------------------------------------------------------------------
create table public.qr_code_histories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  qr_code_id uuid not null references public.qr_codes(id) on delete cascade,
  action text not null check (action in ('generated', 'activated', 'deactivated', 'reassigned')),
  changed_by_user_id uuid references public.app_users(id) on delete set null,
  change_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.qr_code_histories');
create index idx_qr_histories_code on public.qr_code_histories (tenant_id, qr_code_id);
create index idx_qr_histories_user on public.qr_code_histories (tenant_id, changed_by_user_id);
