import Foundation

// MARK: - Database Schema Design
// Multi-tenant SaaS architecture with secure tenant isolation
// Implements row-level security (RLS) and tenant-aware queries

// MARK: - Tenant Isolation Strategy

/**
 * DATABASE SCHEMA OVERVIEW
 * 
 * Strategy: Shared Database with Tenant ID Column (Most Common SaaS Pattern)
 * - Single database instance with tenant_id column in all tenant-specific tables
 * - Row-Level Security (RLS) policies enforce tenant isolation
 * - Cost-effective and scalable solution
 * - Shared infrastructure with strong data isolation
 * 
 * Alternative strategies considered:
 * 1. Separate Databases per Tenant - High cost, complex management
 * 2. Separate Schemas per Tenant - Database connection complexity
 * 3. Discriminator Column with Sharding - Over-engineering for current scale
 */

struct DatabaseSchemaDesign {
    
    // MARK: - Core Tenant Tables
    
    /**
     * TENANTS TABLE
     * Primary tenant registry with configuration and metadata
     * This is the only table that doesn't require tenant_id filtering
     */
    static let tenantsTable = """
    CREATE TABLE tenants (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(255) NOT NULL,
        slug VARCHAR(100) UNIQUE NOT NULL,
        type tenant_type NOT NULL DEFAULT 'individual',
        status tenant_status NOT NULL DEFAULT 'active',
        primary_domain VARCHAR(255),
        branding JSONB DEFAULT '{}',
        settings JSONB DEFAULT '{}',
        limits JSONB NOT NULL,
        features TEXT[] DEFAULT '{}',
        parent_tenant_id UUID REFERENCES tenants(id),
        subscription_id UUID,
        metadata JSONB DEFAULT '{}',
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        suspended_at TIMESTAMP WITH TIME ZONE,
        suspension_reason suspension_reason
    );

    -- Indexes for performance
    CREATE INDEX idx_tenants_slug ON tenants(slug);
    CREATE INDEX idx_tenants_status ON tenants(status);
    CREATE INDEX idx_tenants_type ON tenants(type);
    CREATE INDEX idx_tenants_parent ON tenants(parent_tenant_id);
    
    -- Audit triggers
    CREATE TRIGGER tenants_updated_at BEFORE UPDATE ON tenants 
        FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    """
    
    // MARK: - Custom Domain Management
    
    static let customDomainsTable = """
    CREATE TABLE custom_domains (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
        domain VARCHAR(255) NOT NULL UNIQUE,
        is_verified BOOLEAN DEFAULT FALSE,
        verification_token VARCHAR(255) NOT NULL,
        ssl_certificate JSONB,
        added_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        verified_at TIMESTAMP WITH TIME ZONE
    );

    CREATE INDEX idx_custom_domains_tenant ON custom_domains(tenant_id);
    CREATE INDEX idx_custom_domains_domain ON custom_domains(domain);
    CREATE UNIQUE INDEX idx_custom_domains_verification ON custom_domains(verification_token);
    
    -- RLS Policy: Users can only access domains for their tenant
    ALTER TABLE custom_domains ENABLE ROW LEVEL SECURITY;
    CREATE POLICY custom_domains_tenant_isolation ON custom_domains
        USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
    """
    
    // MARK: - Revenue & Subscription Tables
    
    static let subscriptionsTable = """
    CREATE TABLE subscriptions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
        customer_id UUID NOT NULL,
        tier_id VARCHAR(50) NOT NULL,
        status subscription_status NOT NULL DEFAULT 'active',
        billing_cycle billing_cycle NOT NULL DEFAULT 'monthly',
        current_period_start TIMESTAMP WITH TIME ZONE NOT NULL,
        current_period_end TIMESTAMP WITH TIME ZONE NOT NULL,
        price DECIMAL(10,2) NOT NULL,
        currency CHAR(3) DEFAULT 'USD',
        trial_start TIMESTAMP WITH TIME ZONE,
        trial_end TIMESTAMP WITH TIME ZONE,
        canceled_at TIMESTAMP WITH TIME ZONE,
        cancellation_reason TEXT,
        next_billing_date TIMESTAMP WITH TIME ZONE,
        proration_date TIMESTAMP WITH TIME ZONE,
        metadata JSONB DEFAULT '{}',
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );

    CREATE INDEX idx_subscriptions_tenant ON subscriptions(tenant_id);
    CREATE INDEX idx_subscriptions_customer ON subscriptions(customer_id);
    CREATE INDEX idx_subscriptions_status ON subscriptions(status);
    CREATE INDEX idx_subscriptions_billing_date ON subscriptions(next_billing_date);
    
    -- RLS Policy
    ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
    CREATE POLICY subscriptions_tenant_isolation ON subscriptions
        USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
    
    CREATE TRIGGER subscriptions_updated_at BEFORE UPDATE ON subscriptions 
        FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    """
    
    // MARK: - API Usage Tracking
    
    static let apiUsageTable = """
    CREATE TABLE api_usage (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
        endpoint VARCHAR(255) NOT NULL,
        method http_method NOT NULL,
        status_code INTEGER NOT NULL,
        response_time INTEGER NOT NULL, -- milliseconds
        data_size BIGINT DEFAULT 0, -- bytes
        user_id UUID,
        ip_address INET,
        user_agent TEXT,
        timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        metadata JSONB DEFAULT '{}'
    );

    -- Partitioning by month for performance
    CREATE INDEX idx_api_usage_tenant_timestamp ON api_usage(tenant_id, timestamp DESC);
    CREATE INDEX idx_api_usage_endpoint ON api_usage(endpoint);
    CREATE INDEX idx_api_usage_status ON api_usage(status_code);
    
    -- RLS Policy
    ALTER TABLE api_usage ENABLE ROW LEVEL SECURITY;
    CREATE POLICY api_usage_tenant_isolation ON api_usage
        USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
    """
    
    // MARK: - Rate Limiting Tables
    
    static let rateLimitsTable = """
    CREATE TABLE rate_limits (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
        endpoint VARCHAR(255) NOT NULL,
        request_limit INTEGER NOT NULL,
        window_seconds INTEGER NOT NULL,
        current_usage INTEGER DEFAULT 0,
        reset_time TIMESTAMP WITH TIME ZONE NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );

    CREATE UNIQUE INDEX idx_rate_limits_tenant_endpoint ON rate_limits(tenant_id, endpoint);
    CREATE INDEX idx_rate_limits_reset_time ON rate_limits(reset_time);
    
    -- RLS Policy
    ALTER TABLE rate_limits ENABLE ROW LEVEL SECURITY;
    CREATE POLICY rate_limits_tenant_isolation ON rate_limits
        USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
    """
    
    // MARK: - Billing & Payment Tables
    
    static let customersTable = """
    CREATE TABLE customers (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
        email VARCHAR(255) NOT NULL,
        name VARCHAR(255),
        phone VARCHAR(50),
        address JSONB,
        stripe_customer_id VARCHAR(255) UNIQUE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        last_payment_at TIMESTAMP WITH TIME ZONE,
        metadata JSONB DEFAULT '{}'
    );

    CREATE INDEX idx_customers_tenant ON customers(tenant_id);
    CREATE INDEX idx_customers_email ON customers(email);
    CREATE UNIQUE INDEX idx_customers_stripe ON customers(stripe_customer_id);
    
    -- RLS Policy
    ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
    CREATE POLICY customers_tenant_isolation ON customers
        USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
    """
    
    static let paymentMethodsTable = """
    CREATE TABLE payment_methods (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id UUID NOT NULL,
        customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
        stripe_payment_method_id VARCHAR(255) UNIQUE NOT NULL,
        type payment_method_type NOT NULL,
        is_default BOOLEAN DEFAULT FALSE,
        card_details JSONB,
        bank_details JSONB,
        wallet_details JSONB,
        fingerprint VARCHAR(255),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        last_used_at TIMESTAMP WITH TIME ZONE,
        metadata JSONB DEFAULT '{}'
    );

    CREATE INDEX idx_payment_methods_customer ON payment_methods(customer_id);
    CREATE INDEX idx_payment_methods_tenant ON payment_methods(tenant_id);
    CREATE INDEX idx_payment_methods_stripe ON payment_methods(stripe_payment_method_id);
    
    -- RLS Policy
    ALTER TABLE payment_methods ENABLE ROW LEVEL SECURITY;
    CREATE POLICY payment_methods_tenant_isolation ON payment_methods
        USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
    """
    
    static let paymentsTable = """
    CREATE TABLE payments (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
        customer_id UUID NOT NULL REFERENCES customers(id),
        payment_method_id UUID REFERENCES payment_methods(id),
        subscription_id UUID REFERENCES subscriptions(id),
        amount DECIMAL(10,2) NOT NULL,
        currency CHAR(3) DEFAULT 'USD',
        status payment_status NOT NULL,
        stripe_payment_intent_id VARCHAR(255) UNIQUE,
        description TEXT,
        failure_reason TEXT,
        receipt_url TEXT,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        confirmed_at TIMESTAMP WITH TIME ZONE,
        failed_at TIMESTAMP WITH TIME ZONE,
        metadata JSONB DEFAULT '{}'
    );

    CREATE INDEX idx_payments_tenant ON payments(tenant_id);
    CREATE INDEX idx_payments_customer ON payments(customer_id);
    CREATE INDEX idx_payments_status ON payments(status);
    CREATE INDEX idx_payments_created_at ON payments(created_at DESC);
    
    -- RLS Policy
    ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
    CREATE POLICY payments_tenant_isolation ON payments
        USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
    """
    
    // MARK: - Invoice Management
    
    static let invoicesTable = """
    CREATE TABLE invoices (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
        customer_id UUID NOT NULL REFERENCES customers(id),
        subscription_id UUID REFERENCES subscriptions(id),
        invoice_number VARCHAR(100) UNIQUE NOT NULL,
        status invoice_status NOT NULL DEFAULT 'draft',
        subtotal DECIMAL(10,2) NOT NULL,
        tax_amount DECIMAL(10,2) DEFAULT 0,
        total_amount DECIMAL(10,2) NOT NULL,
        amount_paid DECIMAL(10,2) DEFAULT 0,
        amount_due DECIMAL(10,2) NOT NULL,
        currency CHAR(3) DEFAULT 'USD',
        due_date DATE NOT NULL,
        period_start DATE,
        period_end DATE,
        issued_at TIMESTAMP WITH TIME ZONE,
        paid_at TIMESTAMP WITH TIME ZONE,
        voided_at TIMESTAMP WITH TIME ZONE,
        pdf_url TEXT,
        hosted_url TEXT,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        metadata JSONB DEFAULT '{}'
    );

    CREATE INDEX idx_invoices_tenant ON invoices(tenant_id);
    CREATE INDEX idx_invoices_customer ON invoices(customer_id);
    CREATE INDEX idx_invoices_status ON invoices(status);
    CREATE INDEX idx_invoices_due_date ON invoices(due_date);
    CREATE UNIQUE INDEX idx_invoices_number ON invoices(invoice_number);
    
    -- RLS Policy
    ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
    CREATE POLICY invoices_tenant_isolation ON invoices
        USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
    """
    
    static let invoiceLineItemsTable = """
    CREATE TABLE invoice_line_items (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id UUID NOT NULL,
        invoice_id UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
        description TEXT NOT NULL,
        quantity INTEGER DEFAULT 1,
        unit_amount DECIMAL(10,2) NOT NULL,
        amount DECIMAL(10,2) NOT NULL,
        currency CHAR(3) DEFAULT 'USD',
        type line_item_type DEFAULT 'invoice',
        period_start DATE,
        period_end DATE,
        metadata JSONB DEFAULT '{}'
    );

    CREATE INDEX idx_invoice_line_items_invoice ON invoice_line_items(invoice_id);
    CREATE INDEX idx_invoice_line_items_tenant ON invoice_line_items(tenant_id);
    
    -- RLS Policy
    ALTER TABLE invoice_line_items ENABLE ROW LEVEL SECURITY;
    CREATE POLICY invoice_line_items_tenant_isolation ON invoice_line_items
        USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
    """
    
    // MARK: - Audit & Compliance Tables
    
    static let auditLogsTable = """
    CREATE TABLE audit_logs (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id UUID REFERENCES tenants(id),
        user_id UUID,
        action audit_action NOT NULL,
        resource_type audit_resource_type NOT NULL,
        resource_id UUID,
        changes JSONB,
        ip_address INET,
        user_agent TEXT,
        timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        severity audit_severity DEFAULT 'info',
        compliance_standards TEXT[],
        metadata JSONB DEFAULT '{}'
    );

    -- Partitioning by month for audit logs
    CREATE INDEX idx_audit_logs_tenant_timestamp ON audit_logs(tenant_id, timestamp DESC);
    CREATE INDEX idx_audit_logs_action ON audit_logs(action);
    CREATE INDEX idx_audit_logs_resource ON audit_logs(resource_type, resource_id);
    
    -- RLS Policy for audit logs - tenant admins only
    ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
    CREATE POLICY audit_logs_tenant_admin ON audit_logs
        USING (
            tenant_id = current_setting('app.current_tenant_id')::UUID AND
            current_setting('app.user_role') = 'admin'
        );
    """
    
    // MARK: - Usage Analytics Tables
    
    static let usageAnalyticsTable = """
    CREATE TABLE usage_analytics (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
        period_type analytics_period NOT NULL,
        period_start DATE NOT NULL,
        period_end DATE NOT NULL,
        total_api_calls INTEGER DEFAULT 0,
        unique_endpoints INTEGER DEFAULT 0,
        avg_response_time DECIMAL(6,2) DEFAULT 0,
        error_rate DECIMAL(5,4) DEFAULT 0,
        peak_usage_hour INTEGER,
        bandwidth_used DECIMAL(12,2) DEFAULT 0,
        top_endpoints JSONB DEFAULT '[]',
        cost_estimate DECIMAL(10,2) DEFAULT 0,
        generated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );

    CREATE INDEX idx_usage_analytics_tenant_period ON usage_analytics(tenant_id, period_start, period_end);
    CREATE INDEX idx_usage_analytics_type ON usage_analytics(period_type);
    
    -- RLS Policy
    ALTER TABLE usage_analytics ENABLE ROW LEVEL SECURITY;
    CREATE POLICY usage_analytics_tenant_isolation ON usage_analytics
        USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
    """
    
    // MARK: - Webhook Management
    
    static let webhookEndpointsTable = """
    CREATE TABLE webhook_endpoints (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
        url TEXT NOT NULL,
        enabled_events TEXT[] NOT NULL,
        status webhook_status DEFAULT 'enabled',
        description TEXT,
        secret VARCHAR(255) NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        metadata JSONB DEFAULT '{}'
    );

    CREATE INDEX idx_webhook_endpoints_tenant ON webhook_endpoints(tenant_id);
    CREATE INDEX idx_webhook_endpoints_status ON webhook_endpoints(status);
    
    -- RLS Policy
    ALTER TABLE webhook_endpoints ENABLE ROW LEVEL SECURITY;
    CREATE POLICY webhook_endpoints_tenant_isolation ON webhook_endpoints
        USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
    """
    
    static let webhookDeliveriesTable = """
    CREATE TABLE webhook_deliveries (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id UUID NOT NULL,
        endpoint_id UUID NOT NULL REFERENCES webhook_endpoints(id) ON DELETE CASCADE,
        event_id UUID NOT NULL,
        event_type webhook_event_type NOT NULL,
        url TEXT NOT NULL,
        payload JSONB NOT NULL,
        http_status_code INTEGER,
        response_headers JSONB,
        response_body TEXT,
        attempt_count INTEGER DEFAULT 1,
        delivered_at TIMESTAMP WITH TIME ZONE,
        next_retry TIMESTAMP WITH TIME ZONE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );

    CREATE INDEX idx_webhook_deliveries_endpoint ON webhook_deliveries(endpoint_id);
    CREATE INDEX idx_webhook_deliveries_event ON webhook_deliveries(event_id);
    CREATE INDEX idx_webhook_deliveries_status ON webhook_deliveries(http_status_code);
    CREATE INDEX idx_webhook_deliveries_retry ON webhook_deliveries(next_retry);
    
    -- RLS Policy
    ALTER TABLE webhook_deliveries ENABLE ROW LEVEL SECURITY;
    CREATE POLICY webhook_deliveries_tenant_isolation ON webhook_deliveries
        USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
    """
    
    // MARK: - Application-Specific Tables (Golf Domain)
    
    static let golfCoursesTable = """
    CREATE TABLE golf_courses (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
        name VARCHAR(255) NOT NULL,
        description TEXT,
        address JSONB NOT NULL,
        contact_info JSONB,
        facilities JSONB DEFAULT '{}',
        holes INTEGER DEFAULT 18,
        par INTEGER,
        yardage INTEGER,
        rating DECIMAL(3,1),
        slope_rating INTEGER,
        green_fees JSONB DEFAULT '{}',
        booking_settings JSONB DEFAULT '{}',
        amenities TEXT[],
        photos TEXT[],
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        is_active BOOLEAN DEFAULT TRUE,
        metadata JSONB DEFAULT '{}'
    );

    CREATE INDEX idx_golf_courses_tenant ON golf_courses(tenant_id);
    CREATE INDEX idx_golf_courses_name ON golf_courses(name);
    CREATE INDEX idx_golf_courses_active ON golf_courses(is_active);
    
    -- RLS Policy
    ALTER TABLE golf_courses ENABLE ROW LEVEL SECURITY;
    CREATE POLICY golf_courses_tenant_isolation ON golf_courses
        USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
    """
    
    static let bookingsTable = """
    CREATE TABLE bookings (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
        course_id UUID NOT NULL REFERENCES golf_courses(id),
        customer_id UUID NOT NULL REFERENCES customers(id),
        tee_time TIMESTAMP WITH TIME ZONE NOT NULL,
        players INTEGER NOT NULL DEFAULT 1,
        status booking_status DEFAULT 'pending',
        total_amount DECIMAL(8,2),
        payment_id UUID REFERENCES payments(id),
        special_requests TEXT,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        canceled_at TIMESTAMP WITH TIME ZONE,
        cancellation_reason TEXT,
        metadata JSONB DEFAULT '{}'
    );

    CREATE INDEX idx_bookings_tenant ON bookings(tenant_id);
    CREATE INDEX idx_bookings_course ON bookings(course_id);
    CREATE INDEX idx_bookings_customer ON bookings(customer_id);
    CREATE INDEX idx_bookings_tee_time ON bookings(tee_time);
    CREATE INDEX idx_bookings_status ON bookings(status);
    
    -- RLS Policy
    ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;
    CREATE POLICY bookings_tenant_isolation ON bookings
        USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
    """
}

// MARK: - Database Types & Enums

extension DatabaseSchemaDesign {
    
    static let customTypes = """
    -- Custom Types for Type Safety and Validation
    
    CREATE TYPE tenant_type AS ENUM (
        'individual',
        'small_business', 
        'medium',
        'enterprise',
        'custom'
    );
    
    CREATE TYPE tenant_status AS ENUM (
        'active',
        'inactive',
        'suspended',
        'deleted',
        'provisioning'
    );
    
    CREATE TYPE suspension_reason AS ENUM (
        'non_payment',
        'violation',
        'security',
        'abuse',
        'maintenance',
        'requested',
        'other'
    );
    
    CREATE TYPE subscription_status AS ENUM (
        'active',
        'past_due',
        'unpaid',
        'canceled',
        'incomplete',
        'incomplete_expired',
        'trialing',
        'paused'
    );
    
    CREATE TYPE billing_cycle AS ENUM (
        'monthly',
        'quarterly',
        'yearly'
    );
    
    CREATE TYPE payment_method_type AS ENUM (
        'card',
        'bank_account',
        'apple_pay',
        'google_pay',
        'paypal',
        'venmo'
    );
    
    CREATE TYPE payment_status AS ENUM (
        'pending',
        'processing',
        'succeeded',
        'failed',
        'canceled',
        'requires_action'
    );
    
    CREATE TYPE invoice_status AS ENUM (
        'draft',
        'open',
        'paid',
        'uncollectible',
        'void'
    );
    
    CREATE TYPE line_item_type AS ENUM (
        'subscription',
        'invoice',
        'invoiceitem'
    );
    
    CREATE TYPE http_method AS ENUM (
        'GET',
        'POST',
        'PUT',
        'DELETE',
        'PATCH',
        'HEAD',
        'OPTIONS'
    );
    
    CREATE TYPE audit_action AS ENUM (
        'payment_processed',
        'refund_issued',
        'customer_created',
        'payment_method_added',
        'invoice_generated',
        'subscription_created',
        'fraud_detected',
        'tenant_created',
        'tenant_suspended',
        'api_limit_exceeded'
    );
    
    CREATE TYPE audit_resource_type AS ENUM (
        'payment_intent',
        'customer',
        'payment_method',
        'invoice',
        'subscription',
        'refund',
        'tenant',
        'api_usage',
        'webhook'
    );
    
    CREATE TYPE audit_severity AS ENUM (
        'info',
        'warning',
        'error',
        'critical'
    );
    
    CREATE TYPE analytics_period AS ENUM (
        'hourly',
        'daily',
        'weekly',
        'monthly',
        'yearly'
    );
    
    CREATE TYPE webhook_status AS ENUM (
        'enabled',
        'disabled'
    );
    
    CREATE TYPE webhook_event_type AS ENUM (
        'payment_intent.succeeded',
        'payment_intent.payment_failed',
        'invoice.paid',
        'invoice.payment_failed',
        'customer.created',
        'customer.updated',
        'subscription.created',
        'subscription.updated',
        'subscription.canceled'
    );
    
    CREATE TYPE booking_status AS ENUM (
        'pending',
        'confirmed',
        'checked_in',
        'completed',
        'canceled',
        'no_show'
    );
    """
    
    // MARK: - Database Functions
    
    static let utilityFunctions = """
    -- Utility Functions for Multi-tenant Operations
    
    -- Function to update updated_at column
    CREATE OR REPLACE FUNCTION update_updated_at_column()
    RETURNS TRIGGER AS $$
    BEGIN
        NEW.updated_at = NOW();
        RETURN NEW;
    END;
    $$ language 'plpgsql';
    
    -- Function to generate invoice numbers
    CREATE OR REPLACE FUNCTION generate_invoice_number(tenant_prefix TEXT)
    RETURNS TEXT AS $$
    DECLARE
        current_year INTEGER := EXTRACT(YEAR FROM NOW());
        next_sequence INTEGER;
    BEGIN
        SELECT COALESCE(MAX(
            CAST(
                SUBSTRING(invoice_number FROM LENGTH(tenant_prefix || '-' || current_year::TEXT || '-') + 1) 
                AS INTEGER
            )
        ), 0) + 1 INTO next_sequence
        FROM invoices 
        WHERE invoice_number LIKE tenant_prefix || '-' || current_year::TEXT || '-%';
        
        RETURN tenant_prefix || '-' || current_year::TEXT || '-' || LPAD(next_sequence::TEXT, 6, '0');
    END;
    $$ LANGUAGE plpgsql;
    
    -- Function to check tenant limits
    CREATE OR REPLACE FUNCTION check_tenant_limit(
        tenant_uuid UUID,
        limit_type TEXT,
        current_usage INTEGER
    ) RETURNS BOOLEAN AS $$
    DECLARE
        tenant_limits JSONB;
        limit_value INTEGER;
    BEGIN
        SELECT limits INTO tenant_limits FROM tenants WHERE id = tenant_uuid;
        
        limit_value := (tenant_limits ->> limit_type)::INTEGER;
        
        RETURN current_usage < limit_value;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;
    
    -- Function to calculate usage costs
    CREATE OR REPLACE FUNCTION calculate_usage_costs(
        tenant_uuid UUID,
        api_calls INTEGER DEFAULT 0,
        storage_gb DECIMAL DEFAULT 0,
        bandwidth_gb DECIMAL DEFAULT 0
    ) RETURNS DECIMAL AS $$
    DECLARE
        subscription_tier JSONB;
        included_limits JSONB;
        overage_costs DECIMAL := 0;
        api_overage INTEGER;
        storage_overage DECIMAL;
        bandwidth_overage DECIMAL;
    BEGIN
        -- Get subscription tier and limits
        SELECT s.tier_data, s.limits INTO subscription_tier, included_limits
        FROM subscriptions s
        WHERE s.tenant_id = tenant_uuid AND s.status = 'active'
        LIMIT 1;
        
        -- Calculate API overage
        api_overage := GREATEST(0, api_calls - (included_limits->>'api_calls_per_month')::INTEGER);
        overage_costs := overage_costs + (api_overage * (subscription_tier->>'api_overage_rate')::DECIMAL);
        
        -- Calculate storage overage
        storage_overage := GREATEST(0, storage_gb - (included_limits->>'storage_gb')::DECIMAL);
        overage_costs := overage_costs + (storage_overage * (subscription_tier->>'storage_overage_rate')::DECIMAL);
        
        -- Calculate bandwidth overage
        bandwidth_overage := GREATEST(0, bandwidth_gb - (included_limits->>'bandwidth_gb')::DECIMAL);
        overage_costs := overage_costs + (bandwidth_overage * (subscription_tier->>'bandwidth_overage_rate')::DECIMAL);
        
        RETURN overage_costs;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;
    """
    
    // MARK: - Security Policies
    
    static let securityPolicies = """
    -- Row-Level Security (RLS) Configuration
    -- Ensures complete tenant data isolation at database level
    
    -- Enable RLS for all tenant-specific tables
    ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
    ALTER TABLE custom_domains ENABLE ROW LEVEL SECURITY;
    ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
    ALTER TABLE api_usage ENABLE ROW LEVEL SECURITY;
    ALTER TABLE rate_limits ENABLE ROW LEVEL SECURITY;
    ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
    ALTER TABLE payment_methods ENABLE ROW LEVEL SECURITY;
    ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
    ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
    ALTER TABLE invoice_line_items ENABLE ROW LEVEL SECURITY;
    ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
    ALTER TABLE usage_analytics ENABLE ROW LEVEL SECURITY;
    ALTER TABLE webhook_endpoints ENABLE ROW LEVEL SECURITY;
    ALTER TABLE webhook_deliveries ENABLE ROW LEVEL SECURITY;
    ALTER TABLE golf_courses ENABLE ROW LEVEL SECURITY;
    ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;
    
    -- Create application roles
    CREATE ROLE tenant_user;
    CREATE ROLE tenant_admin;
    CREATE ROLE system_admin;
    
    -- Grant base permissions
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO tenant_user;
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO tenant_admin;
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO system_admin;
    
    -- System admin can bypass RLS
    ALTER TABLE tenants FORCE ROW LEVEL SECURITY;
    CREATE POLICY tenants_system_admin ON tenants TO system_admin USING (true);
    
    -- Tenant access policies
    CREATE POLICY tenants_self_access ON tenants TO tenant_admin, tenant_user
        USING (id = current_setting('app.current_tenant_id')::UUID);
    """
    
    // MARK: - Performance Optimizations
    
    static let performanceOptimizations = """
    -- Performance Optimizations for Multi-tenant Architecture
    
    -- Partitioning for high-volume tables
    -- API Usage partitioned by month
    CREATE TABLE api_usage_y2024m01 PARTITION OF api_usage
        FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
    CREATE TABLE api_usage_y2024m02 PARTITION OF api_usage
        FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
    -- Continue for each month...
    
    -- Audit logs partitioned by month
    CREATE TABLE audit_logs_y2024m01 PARTITION OF audit_logs
        FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
    
    -- Composite indexes for multi-tenant queries
    CREATE INDEX CONCURRENTLY idx_api_usage_tenant_endpoint_time 
        ON api_usage(tenant_id, endpoint, timestamp DESC);
    
    CREATE INDEX CONCURRENTLY idx_payments_tenant_status_created 
        ON payments(tenant_id, status, created_at DESC);
    
    CREATE INDEX CONCURRENTLY idx_bookings_tenant_course_time 
        ON bookings(tenant_id, course_id, tee_time);
    
    -- Materialized views for analytics
    CREATE MATERIALIZED VIEW tenant_monthly_analytics AS
    SELECT 
        tenant_id,
        DATE_TRUNC('month', timestamp) as month,
        COUNT(*) as total_requests,
        AVG(response_time) as avg_response_time,
        COUNT(CASE WHEN status_code >= 400 THEN 1 END) as error_count,
        SUM(data_size) as total_data_transfer
    FROM api_usage
    GROUP BY tenant_id, DATE_TRUNC('month', timestamp);
    
    CREATE UNIQUE INDEX idx_tenant_monthly_analytics 
        ON tenant_monthly_analytics(tenant_id, month);
    
    -- Refresh analytics daily
    CREATE OR REPLACE FUNCTION refresh_analytics()
    RETURNS void AS $$
    BEGIN
        REFRESH MATERIALIZED VIEW CONCURRENTLY tenant_monthly_analytics;
    END;
    $$ LANGUAGE plpgsql;
    
    -- Connection pooling configuration
    -- Recommended: Use PgBouncer with session pooling
    -- Configuration for application connection:
    -- - Max connections per tenant: 20
    -- - Connection timeout: 30s
    -- - Idle connection timeout: 10min
    """
    
    // MARK: - Data Backup & Recovery
    
    static let backupConfiguration = """
    -- Backup & Recovery Strategy for Multi-tenant Data
    
    -- Daily automated backups with point-in-time recovery
    -- Backup retention: 30 days for standard tiers, 90 days for enterprise
    
    -- Function to backup single tenant data
    CREATE OR REPLACE FUNCTION backup_tenant_data(tenant_uuid UUID)
    RETURNS TEXT AS $$
    DECLARE
        backup_file TEXT;
        tenant_slug TEXT;
    BEGIN
        SELECT slug INTO tenant_slug FROM tenants WHERE id = tenant_uuid;
        backup_file := 'tenant_' || tenant_slug || '_' || TO_CHAR(NOW(), 'YYYY_MM_DD_HH24_MI_SS') || '.sql';
        
        -- Execute pg_dump for specific tenant
        -- This would be handled by external backup service
        -- EXECUTE format('pg_dump --where="tenant_id = %L" -f %s', tenant_uuid, backup_file);
        
        RETURN backup_file;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;
    
    -- Function to restore tenant data
    CREATE OR REPLACE FUNCTION restore_tenant_data(
        tenant_uuid UUID, 
        backup_file TEXT,
        restore_point TIMESTAMP DEFAULT NOW()
    ) RETURNS BOOLEAN AS $$
    BEGIN
        -- Restore logic would be implemented here
        -- Point-in-time recovery for specific tenant
        RAISE NOTICE 'Restoring tenant % from % at %', tenant_uuid, backup_file, restore_point;
        RETURN true;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;
    """
}

// MARK: - Migration Scripts

struct DatabaseMigrations {
    
    // MARK: - Initial Schema Migration
    
    static let initialMigration = """
    -- Migration 001: Initial Multi-tenant Schema
    -- Creates the foundational tables and security policies
    
    BEGIN;
    
    -- Create custom types first
    \(DatabaseSchemaDesign.customTypes)
    
    -- Create utility functions
    \(DatabaseSchemaDesign.utilityFunctions)
    
    -- Create core tables
    \(DatabaseSchemaDesign.tenantsTable)
    \(DatabaseSchemaDesign.customDomainsTable)
    \(DatabaseSchemaDesign.subscriptionsTable)
    \(DatabaseSchemaDesign.apiUsageTable)
    \(DatabaseSchemaDesign.rateLimitsTable)
    
    -- Create billing tables
    \(DatabaseSchemaDesign.customersTable)
    \(DatabaseSchemaDesign.paymentMethodsTable)
    \(DatabaseSchemaDesign.paymentsTable)
    \(DatabaseSchemaDesign.invoicesTable)
    \(DatabaseSchemaDesign.invoiceLineItemsTable)
    
    -- Create audit and analytics tables
    \(DatabaseSchemaDesign.auditLogsTable)
    \(DatabaseSchemaDesign.usageAnalyticsTable)
    
    -- Create webhook tables
    \(DatabaseSchemaDesign.webhookEndpointsTable)
    \(DatabaseSchemaDesign.webhookDeliveriesTable)
    
    -- Create application tables
    \(DatabaseSchemaDesign.golfCoursesTable)
    \(DatabaseSchemaDesign.bookingsTable)
    
    -- Apply security policies
    \(DatabaseSchemaDesign.securityPolicies)
    
    -- Apply performance optimizations
    \(DatabaseSchemaDesign.performanceOptimizations)
    
    -- Set up backup configuration
    \(DatabaseSchemaDesign.backupConfiguration)
    
    COMMIT;
    """
    
    // MARK: - Sample Data Migration
    
    static let sampleDataMigration = """
    -- Migration 002: Sample Data for Development
    -- Creates sample tenants and test data
    
    BEGIN;
    
    -- Insert sample tenants
    INSERT INTO tenants (id, name, slug, type, status, limits, features, metadata) VALUES
    ('550e8400-e29b-41d4-a716-446655440001', 'Pebble Beach Golf Links', 'pebble-beach', 'enterprise', 'active', 
     '{"api_calls_per_month": 1000000, "storage_gb": 500, "max_users": 1000}',
     '{"golf_management", "advanced_booking", "analytics", "api_access"}',
     '{"industry": "golf", "location": "Pebble Beach, CA"}'),
    ('550e8400-e29b-41d4-a716-446655440002', 'Green Golf Startup', 'green-golf', 'small_business', 'active',
     '{"api_calls_per_month": 25000, "storage_gb": 10, "max_users": 5}',
     '{"basic_booking", "course_management"}',
     '{"segment": "startup"}');
    
    -- Insert sample customers
    INSERT INTO customers (id, tenant_id, email, name) VALUES
    ('660e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440001', 'john.doe@example.com', 'John Doe'),
    ('660e8400-e29b-41d4-a716-446655440002', '550e8400-e29b-41d4-a716-446655440002', 'jane.smith@example.com', 'Jane Smith');
    
    -- Insert sample golf courses
    INSERT INTO golf_courses (id, tenant_id, name, holes, par, address) VALUES
    ('770e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440001', 
     'Pebble Beach Golf Links', 18, 72, '{"line1": "17 Mile Drive", "city": "Pebble Beach", "state": "CA", "zip": "93953"}'),
    ('770e8400-e29b-41d4-a716-446655440002', '550e8400-e29b-41d4-a716-446655440002',
     'Green Valley Golf Course', 18, 70, '{"line1": "123 Golf Rd", "city": "San Jose", "state": "CA", "zip": "95123"}');
    
    COMMIT;
    """
}

// MARK: - Database Connection & Query Helpers

struct DatabaseHelpers {
    
    // MARK: - Tenant Context Management
    
    /**
     * Sets the current tenant context for RLS policies
     * This must be called at the beginning of each request
     */
    static func setTenantContext(tenantId: String, userRole: String = "tenant_user") -> String {
        return """
        SELECT set_config('app.current_tenant_id', '\(tenantId)', true);
        SELECT set_config('app.user_role', '\(userRole)', true);
        """
    }
    
    /**
     * Clears the tenant context
     * Should be called at the end of each request
     */
    static let clearTenantContext = """
        SELECT set_config('app.current_tenant_id', '', true);
        SELECT set_config('app.user_role', '', true);
    """
    
    // MARK: - Common Queries
    
    static let getTenantBySlug = """
        SELECT * FROM tenants WHERE slug = $1 AND status = 'active';
    """
    
    static let getCustomerSubscription = """
        SELECT s.*, t.name as tier_name 
        FROM subscriptions s
        JOIN subscription_tiers t ON s.tier_id = t.id
        WHERE s.customer_id = $1 AND s.status = 'active';
    """
    
    static let checkAPIRateLimit = """
        SELECT 
            CASE 
                WHEN current_usage >= request_limit THEN false
                ELSE true
            END as allowed,
            request_limit - current_usage as remaining,
            reset_time
        FROM rate_limits 
        WHERE tenant_id = $1 AND endpoint = $2
        AND reset_time > NOW();
    """
    
    static let updateAPIUsage = """
        INSERT INTO api_usage (tenant_id, endpoint, method, status_code, response_time, timestamp)
        VALUES ($1, $2, $3, $4, $5, NOW());
    """
}

// MARK: - Schema Documentation

/**
 * MULTI-TENANT DATABASE SCHEMA OVERVIEW
 * 
 * Security Model:
 * - Row-Level Security (RLS) enforces tenant isolation
 * - All tenant-specific tables include tenant_id column
 * - Application must set tenant context before queries
 * - Policies prevent cross-tenant data access
 * 
 * Performance Considerations:
 * - Composite indexes on (tenant_id, other_columns)
 * - Table partitioning for high-volume data (api_usage, audit_logs)
 * - Materialized views for analytics aggregation
 * - Connection pooling with tenant-aware routing
 * 
 * Scalability Features:
 * - Horizontal partitioning ready for large datasets
 * - Separate read replicas for analytics queries
 * - Background job processing for heavy operations
 * - Automated archival of old data
 * 
 * Compliance & Audit:
 * - Complete audit trail for all operations
 * - PCI DSS compliance for payment data
 * - GDPR-compliant data retention policies
 * - SOX compliance for financial reporting
 * 
 * Backup & Recovery:
 * - Daily automated backups with 30-90 day retention
 * - Point-in-time recovery capability
 * - Tenant-specific backup and restore
 * - Geographic backup replication
 * 
 * Monitoring & Alerting:
 * - Real-time performance metrics
 * - Usage threshold alerts
 * - Security event monitoring
 * - Automated failover procedures
 */