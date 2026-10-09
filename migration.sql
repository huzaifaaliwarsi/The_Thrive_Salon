-- Migration for Payment Accounts and Multi-Payment Breakdown
-- Safe to run multiple times: uses IF NOT EXISTS and preserves all existing data.

CREATE TABLE IF NOT EXISTS public.payment_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    salon_id UUID NOT NULL REFERENCES public.salons(id) ON DELETE CASCADE,
    account_name TEXT NOT NULL,
    account_title TEXT,
    account_number TEXT,
    iban TEXT,
    type TEXT DEFAULT 'BANK',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_accounts_salon_id ON public.payment_accounts(salon_id);

ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS payment_account_id UUID REFERENCES public.payment_accounts(id) ON DELETE SET NULL;
ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS payment_breakdown TEXT;

ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'CASH';
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS payment_account_id UUID REFERENCES public.payment_accounts(id) ON DELETE SET NULL;
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS payment_breakdown TEXT;

ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS payment_account_id UUID REFERENCES public.payment_accounts(id) ON DELETE SET NULL;
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS payment_breakdown TEXT;

ALTER TABLE public.salary_deductions ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'CASH';
ALTER TABLE public.salary_deductions ADD COLUMN IF NOT EXISTS payment_account_id UUID REFERENCES public.payment_accounts(id) ON DELETE SET NULL;
