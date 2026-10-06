# Online Payment Accounts & Sub-Category Breakdown — Architecture & Implementation Plan

---

## 1. Executive Summary & Objective

Currently, the system records payments with a flat `ONLINE` payment method (e.g., Total Online: PKR 10,000). Salon owners receive online payments across multiple physical banks and mobile wallets (such as **JazzCash, EasyPaisa, Meezan Bank, HBL, Nayapay**, etc.).

### Goal
1. **Dynamic Payment Accounts in Settings:** Salon owners can configure their bank and wallet accounts (e.g., Meezan Bank, JazzCash) from Settings.
2. **Account Selection & Breakdown at Checkout (POS):** When selecting `ONLINE` as the payment method, cashier can select which account received the funds, or split between multiple accounts (e.g., `JazzCash = 1000 PKR`, `Meezan Bank = 200 PKR`).
3. **Sub-Category Reporting:** In all financial reports, sales summaries, and Galla/drawer views, wherever "Online Amount" is reported, it will display the breakdown per bank account:
   ```text
   Online Received: PKR 1,200
     ├─ JazzCash:    PKR 1,000
     └─ Meezan Bank: PKR 200
   ```
4. **Zero Production Risk & Backward Compatibility:** Existing sales and historical reports must continue to work without breaking live data.

---

## 2. Codebase Audit: Where `ONLINE` & `paymentMethod` Currently Exist

| Component | File Path | Existing Logic & Needed Modifications |
| :--- | :--- | :--- |
| **Database Schema** | `backend/src/db/schema.ts` | Need `payment_accounts` table + optional `payment_account_id` / `payment_breakdown` in `sales` and `ledger_entries`. |
| **Sales API** | `backend/src/routes/sales.ts` | Line 15, 230–285: Processes payments and creates `ledger_entries`. Needs to record selected `paymentAccountId` / `onlineBreakdown`. |
| **Ledger & Galla Engine** | `backend/src/utils/ledger.ts` | Lines 5–44 (`isOnlineSql`), lines 107–240 (`getSalonGallaBalances`): Needs to aggregate balances per account (`onlineBreakdown: { [accountName]: amount }`). |
| **Reports API** | `backend/src/routes/reports.ts` | Lines 35–250 (`/summary`), lines 1154–1200 (`drawerBalances`): Needs to expose `onlineBreakdown` in responses. |
| **Dashboard API** | `backend/src/routes/dashboard.ts` | Line 84 (`getSalonGallaBalances`): Needs to return `onlineBreakdown` for today's drawer card. |
| **Expenses & Purchases** | `backend/src/routes/expenses.ts`, `purchases.ts` | Optional: Allow selecting bank account when paying an expense or supplier bill online. |
| **Settings UI** | `mobile/lib/views/salon_settings_view.dart` | Add "Bank & Online Payment Accounts" configuration card (CRUD for accounts). |
| **POS View Model** | `mobile/lib/view_models/pos_view_model.dart` | Manage selected `paymentAccountId` / `onlineSplits` state during checkout. |
| **POS Checkout UI** | `mobile/lib/views/pos_view.dart` | Lines 1302–1328 (`_PaymentToggleSection`): When `ONLINE` is tapped, show account selector / split modal. |
| **Drawer Tab** | `mobile/lib/views/reports/tabs/drawer_tab.dart` | Lines 30–65, 87–120: Display expandable sub-categories for each bank account under Online Sales. |
| **Sales Tab** | `mobile/lib/views/reports/tabs/sales_tab.dart` | Include bank account name in sale details and payment filters. |
| **Overview Tab** | `mobile/lib/views/reports/tabs/overview_tab.dart` | Render sub-breakdown under the Online Revenue metric card. |
| **Public Invoice** | `mobile/lib/views/public_invoice_view.dart` | Show bank name if paid online (e.g., "Paid via JazzCash"). |

---

## 3. Database Architecture (Non-Breaking Design)

### 3.1 New Table: `payment_accounts`
```sql
CREATE TABLE IF NOT EXISTS public.payment_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  salon_id UUID NOT NULL REFERENCES public.salons(id) ON DELETE CASCADE,
  account_name TEXT NOT NULL,         -- e.g. "Meezan Bank", "JazzCash"
  account_title TEXT,                 -- e.g. "The Thrive Salon"
  account_number TEXT,                -- e.g. "010203040506" / "03001234567"
  type TEXT DEFAULT 'BANK',           -- 'BANK', 'WALLET', 'CARD_MACHINE'
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_payment_accounts_salon_id ON public.payment_accounts(salon_id);
```

### 3.2 Additions to Existing Tables (Fully Backward-Compatible):
* **`sales` table:**
  * Add `payment_account_id UUID REFERENCES payment_accounts(id)` (NULLABLE).
  * Add `payment_breakdown JSONB` (NULLABLE) — e.g. `[{"accountId": "...", "accountName": "JazzCash", "amount": 1000}, {"accountId": "...", "accountName": "Meezan Bank", "amount": 200}]`.
* **`ledger_entries` table:**
  * In `notes` JSON field, include `paymentAccountId` and `paymentAccountName`.
  * Add `payment_account_id UUID REFERENCES payment_accounts(id)` (NULLABLE).

> **Why this is 100% safe for production:**
> All new columns are optional/nullable. Old sales will have `NULL` and will gracefully fall back to "General Online", so zero existing data will be corrupted or invalidated.

---

## 4. API Endpoints Specification

### 4.1 Payment Accounts CRUD
* `GET /api/payment-accounts`
  * Fetches active payment accounts for the authenticated user's salon.
* `POST /api/payment-accounts`
  * Body: `{ accountName: "Meezan Bank", accountTitle: "Thrive Salon", accountNumber: "029101...", type: "BANK" }`
* `PUT /api/payment-accounts/:id`
  * Updates account details.
* `DELETE /api/payment-accounts/:id`
  * Soft-deletes or disables the account (`is_active: false`).

### 4.2 Updated Sale Creation (`POST /api/sales`)
Accepts either single account or multi-account split:
```json
{
  "customerName": "Fatima Khan",
  "total": 1200,
  "paymentMethod": "ONLINE",
  "amountPaid": 1200,
  "onlineBreakdown": [
    { "accountId": "uuid-1", "accountName": "JazzCash", "amount": 1000 },
    { "accountId": "uuid-2", "accountName": "Meezan Bank", "amount": 200 }
  ]
}
```

### 4.3 Updated Reports / Galla Response (`GET /api/reports/summary`)
```json
{
  "totalSales": 15000,
  "cashSales": 5000,
  "onlineSales": 10000,
  "onlineBreakdown": {
    "JazzCash": 6000,
    "Meezan Bank": 4000
  },
  "drawerBalances": {
    "cashBalance": 4500,
    "onlineBalance": 10000,
    "onlineBreakdown": {
      "JazzCash": 6000,
      "Meezan Bank": 4000
    }
  }
}
```

---

## 5. Frontend (Flutter) UI Plan

### 5.1 Settings Screen (`salon_settings_view.dart`)
* New Card: **"Bank & Online Payment Accounts"**
* Button: **"+ Add Account"** (Dialog with Name, Title, Number, Type).
* List of existing accounts with edit and active/inactive toggle switches.

### 5.2 POS Checkout (`pos_view.dart`)
* When user clicks **`ONLINE`** under Payment Method:
  * If only 1 account configured: Automatically selects that account.
  * If multiple accounts exist: Displays quick chips/selector (e.g. `[JazzCash]` `[Meezan Bank]`).
  * If customer pays via multiple banks (Split Online): A popup allows entering amounts (e.g. `1000` in JazzCash and `200` in Meezan).

### 5.3 Reports & Galla Drawer (`drawer_tab.dart` & `overview_tab.dart`)
* Under the **"Online Sales / Payments"** card:
  * An expandable accordion or clean indented list showing:
    ```
    Online Revenue: PKR 10,000
      • JazzCash:    PKR 6,000
      • Meezan Bank: PKR 4,000
    ```

---

## 6. Implementation Timeline & Working Days Estimate

| Phase | Tasks | Estimated Duration |
| :--- | :--- | :--- |
| **Phase 1: Database & Backend Engine** | • Create `payment_accounts` table migration in local DB.<br>• Implement `/api/payment-accounts` CRUD.<br>• Update `sales.ts` and `ledger.ts` to accept & store account breakdown.<br>• Update `getSalonGallaBalances` to aggregate online breakdown. | **1 Working Day** |
| **Phase 2: Settings & Management UI** | • Create `payment_accounts_provider.dart` in Flutter.<br>• Implement Account Management UI in `salon_settings_view.dart` (Add, Edit, Toggle). | **0.5 - 1 Working Day** |
| **Phase 3: POS Billing Integration** | • Update `pos_view_model.dart` and `pos_view.dart` for account selection and multi-bank split.<br>• Update print receipt & invoice view to reflect selected bank. | **1 Working Day** |
| **Phase 4: Reports & Dashboard Breakdown** | • Update `reports.ts` and `dashboard.ts` endpoints.<br>• Update Flutter `drawer_tab.dart`, `sales_tab.dart`, `overview_tab.dart` with sub-category UI. | **1 Working Day** |
| **Phase 5: Local Testing & Verification** | • End-to-end testing with local database (create sales, test split payments, verify reports).<br>• Edge cases verification (void sales, refunds, expenses). | **0.5 Working Day** |
| **Total Estimated Time** | **Complete Feature Implementation** | **3.5 to 4 Working Days** |

---

## 7. Deployment Safety & Zero-Downtime Strategy

1. **Step 1 (Database Migration):** Run the `CREATE TABLE payment_accounts` and `ALTER TABLE sales ADD COLUMN ...` on production PostgreSQL first. Because columns are nullable, this takes < 1 second and produces zero downtime.
2. **Step 2 (Backend Deploy):** Deploy the updated backend Node code. It supports both new sales (with account breakdown) and legacy sales (fallback to General Online).
3. **Step 3 (Frontend Deploy):** Build Flutter web with `--dart-define-from-file=config/production.json` and upload to cPanel.
