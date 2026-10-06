# 10-Step Implementation Roadmap: Multi-Account Online Payments

This document provides a sequential, 10-step execution blueprint for implementing dynamic online payment accounts (e.g., JazzCash, Meezan Bank) with sub-category reporting across POS checkout, ledger, and drawer balances. Any developer or AI agent can follow these steps in order.

---

## Step 1: Database Schema Migration
* **Objective:** Create the `payment_accounts` table and add backward-compatible, nullable columns to `sales` and `ledger_entries`.
* **Target Files:**
  * [`backend/src/db/schema.ts`](file:///d:/Isysware%20works/Thrive-Salon-main/backend/src/db/schema.ts)
  * Local PostgreSQL DB (`127.0.0.1:55433/thrive_local`)
* **Actions:**
  1. Define `paymentAccounts` in `schema.ts`:
     ```typescript
     export const paymentAccounts = pgTable('payment_accounts', {
       id: uuid('id').defaultRandom().primaryKey(),
       salonId: uuid('salon_id').notNull().references(() => salons.id, { onDelete: 'cascade' }),
       accountName: text('account_name').notNull(),    // e.g. "Meezan Bank", "JazzCash"
       accountTitle: text('account_title'),            // e.g. "The Thrive Salon"
       accountNumber: text('account_number'),          // e.g. "03001234567"
       type: text('type').default('BANK'),             // 'BANK', 'WALLET', 'POS_MACHINE'
       isActive: boolean('is_active').default(true),
       createdAt: timestamp('created_at').default(sql`now()`),
       updatedAt: timestamp('updated_at').default(sql`now()`),
     });
     ```
  2. Add optional, nullable fields to `sales`:
     * `paymentAccountId: uuid('payment_account_id').references(() => paymentAccounts.id)`
     * `paymentBreakdown: text('payment_breakdown')` (Stores JSON string: `[{"accountId":"...","accountName":"JazzCash","amount":1000},{"accountId":"...","accountName":"Meezan Bank","amount":200}]`)
  3. Execute SQL migration on local DB:
     ```sql
     CREATE TABLE IF NOT EXISTS public.payment_accounts (
       id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
       salon_id UUID NOT NULL REFERENCES public.salons(id) ON DELETE CASCADE,
       account_name TEXT NOT NULL,
       account_title TEXT,
       account_number TEXT,
       type TEXT DEFAULT 'BANK',
       is_active BOOLEAN DEFAULT true,
       created_at TIMESTAMPTZ DEFAULT now(),
       updated_at TIMESTAMPTZ DEFAULT now()
     );
     ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS payment_account_id UUID REFERENCES public.payment_accounts(id);
     ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS payment_breakdown TEXT;
     ```
* **Done Criteria:** `payment_accounts` table exists in pgAdmin under `thrive_local`, and `backend` compiles with `npm run build`.

---

## Step 2: Payment Accounts Backend CRUD API
* **Objective:** Provide secure REST endpoints for salons to configure their bank/wallet accounts.
* **Target Files:**
  * `backend/src/routes/paymentAccounts.ts` (New file)
  * [`backend/src/index.ts`](file:///d:/Isysware%20works/Thrive-Salon-main/backend/src/index.ts)
* **Actions:**
  1. Create router `paymentAccounts.ts` with authentication and salon check middleware:
     * `GET /api/payment-accounts` -> Lists all active accounts for `req.user.salonId`.
     * `POST /api/payment-accounts` -> Creates a new account (`accountName`, `accountTitle`, `accountNumber`, `type`).
     * `PUT /api/payment-accounts/:id` -> Updates account details.
     * `DELETE /api/payment-accounts/:id` -> Soft deletes (`isActive = false`).
  2. Mount router in `backend/src/index.ts`:
     ```typescript
     import paymentAccountsRouter from './routes/paymentAccounts';
     // ...
     app.use('/api/payment-accounts', paymentAccountsRouter);
     ```
* **Done Criteria:** Test `GET /api/payment-accounts` and `POST /api/payment-accounts` with `curl` or Postman using the owner token and verify 200 OK.

---

## Step 3: POS Sales Engine Enhancement (Multi-Account Recording)
* **Objective:** Enable `POST /api/sales` to receive online account allocations and create detailed ledger entries.
* **Target Files:**
  * [`backend/src/routes/sales.ts`](file:///d:/Isysware%20works/Thrive-Salon-main/backend/src/routes/sales.ts)
* **Actions:**
  1. In `POST /api/sales` and `POST /api/sales/draft`:
     * Read `paymentAccountId` and `onlineBreakdown` from `req.body`.
     * Store `paymentBreakdown: JSON.stringify(onlineBreakdown)` in the new `sales` record.
  2. In ledger entry creation (lines 271–285):
     * If `onlineBreakdown` is provided (e.g., `[{accountName: 'JazzCash', amount: 1000}, {accountName: 'Meezan Bank', amount: 200}]`):
       Create a separate `ledger_entries` row for each account with structured JSON in `notes`:
       ```json
       {
         "paymentMethod": "ONLINE",
         "paymentAccountId": "uuid",
         "paymentAccountName": "JazzCash",
         "userNotes": "Amount Paid at Sale (JazzCash) - Sale #1234"
       }
       ```
     * If `onlineBreakdown` is not provided (legacy/single account): Fall back to default single entry.
* **Done Criteria:** A test sale with `onlineBreakdown` creates distinct ledger rows for JazzCash and Meezan Bank in `thrive_local`.

---

## Step 4: Galla & Ledger Engine Update (Per-Account Aggregation)
* **Objective:** Enhance `getSalonGallaBalances` to aggregate online balances per bank account.
* **Target Files:**
  * [`backend/src/utils/ledger.ts`](file:///d:/Isysware%20works/Thrive-Salon-main/backend/src/utils/ledger.ts)
* **Actions:**
  1. Add helper `getPaymentAccountFromEntry(entry)` to extract `paymentAccountName` or fallback to `'Other Online'`.
  2. In `getSalonGallaBalances`:
     * Add `onlineBreakdown: Record<string, number> = {}` (e.g. `{"JazzCash": 5000, "Meezan Bank": 3000}`).
     * In the entries loop, whenever an online payment is processed:
       ```typescript
       const acct = getPaymentAccountFromEntry(entry) || 'Other Online';
       onlineBreakdown[acct] = (onlineBreakdown[acct] || 0) + amt;
       ```
     * Return `onlineBreakdown` in the return object alongside `onlineSales` and `onlineBalance`.
* **Done Criteria:** Calling `getSalonGallaBalances(salonId)` returns `{ onlineSales: 8000, onlineBreakdown: { "JazzCash": 5000, "Meezan Bank": 3000 } }`.

---

## Step 5: Reports & Dashboard APIs Update
* **Objective:** Expose the sub-category online breakdown in all reporting endpoints.
* **Target Files:**
  * [`backend/src/routes/reports.ts`](file:///d:/Isysware%20works/Thrive-Salon-main/backend/src/routes/reports.ts)
  * [`backend/src/routes/dashboard.ts`](file:///d:/Isysware%20works/Thrive-Salon-main/backend/src/routes/dashboard.ts)
* **Actions:**
  1. In `reports.ts`:
     * In `/summary` response, include `onlineBreakdown` in `totalSalesResult` and `drawerBalances`.
  2. In `dashboard.ts`:
     * In `/metrics` response, include `onlineBreakdown` inside the drawer/galla stats.
* **Done Criteria:** `GET /api/reports/summary` returns `onlineBreakdown` object containing amounts grouped by bank account.

---

## Step 6: Frontend API Service & Riverpod State Providers
* **Objective:** Create the Dart models, API methods, and Riverpod providers for payment accounts.
* **Target Files:**
  * `mobile/lib/models/payment_account.dart` (New file)
  * [`mobile/lib/services/api_service.dart`](file:///d:/Isysware%20works/Thrive-Salon-main/mobile/lib/services/api_service.dart)
  * `mobile/lib/providers/payment_accounts_provider.dart` (New file)
* **Actions:**
  1. Create model `PaymentAccount` (`id`, `salonId`, `accountName`, `accountTitle`, `accountNumber`, `type`, `isActive`).
  2. Add methods in `api_service.dart`:
     * `getPaymentAccounts()`
     * `createPaymentAccount(Map<String, dynamic> data)`
     * `updatePaymentAccount(String id, Map<String, dynamic> data)`
     * `deletePaymentAccount(String id)`
  3. Create Riverpod provider `paymentAccountsProvider` to fetch and cache accounts list.
* **Done Criteria:** Flutter code compiles cleanly without errors.

---

## Step 7: Salon Settings UI — Payment Accounts Management
* **Objective:** Give salon owners an interface in Settings to manage their bank accounts.
* **Target Files:**
  * [`mobile/lib/views/salon_settings_view.dart`](file:///d:/Isysware%20works/Thrive-Salon-main/mobile/lib/views/salon_settings_view.dart)
* **Actions:**
  1. Add a new card in `SalonSettingsView`: **"Online Payment & Bank Accounts"**.
  2. Show a list of configured accounts with:
     * Icon (Bank or Wallet).
     * Account Name (e.g., JazzCash, Meezan Bank).
     * Account Number and Title.
     * Edit button and active/inactive toggle switch.
  3. Add an **"+ Add Account"** button that opens a dialog to enter Name, Title, and Number.
* **Done Criteria:** An owner can add "JazzCash" and "Meezan Bank" in Settings, and they appear in the list.

---

## Step 8: POS Checkout UI & Multi-Bank Allocation
* **Objective:** Allow cashiers to assign online payments to single or multiple bank accounts at checkout.
* **Target Files:**
  * [`mobile/lib/view_models/pos_view_model.dart`](file:///d:/Isysware%20works/Thrive-Salon-main/mobile/lib/view_models/pos_view_model.dart)
  * [`mobile/lib/views/pos_view.dart`](file:///d:/Isysware%20works/Thrive-Salon-main/mobile/lib/views/pos_view.dart)
* **Actions:**
  1. In `pos_view_model.dart`:
     * Add `selectedPaymentAccountId` and `onlineBreakdown: List<Map<String, dynamic>>` to `PosState`.
     * Add methods `setPaymentAccount(id)` and `setOnlineBreakdown(list)`.
  2. In `pos_view.dart`:
     * When cashier taps **`ONLINE`**:
       * If multiple accounts exist, show an account selector dropdown/chips.
       * If customer splits online (e.g. JazzCash = 1000 PKR, Meezan = 200 PKR), show a **"Split Online"** modal where cashier enters amounts per account.
     * Send `onlineBreakdown` in `_processSale` payload to the backend.
* **Done Criteria:** Complete a POS checkout with JazzCash = 1000 and Meezan Bank = 200 without validation errors.

---

## Step 9: Reports & Galla Drawer UI — Sub-Category Breakdown Display
* **Objective:** Display the per-account online breakdown in Drawer, Sales, and Overview tabs.
* **Target Files:**
  * [`mobile/lib/views/reports/tabs/drawer_tab.dart`](file:///d:/Isysware%20works/Thrive-Salon-main/mobile/lib/views/reports/tabs/drawer_tab.dart)
  * [`mobile/lib/views/reports/tabs/sales_tab.dart`](file:///d:/Isysware%20works/Thrive-Salon-main/mobile/lib/views/reports/tabs/sales_tab.dart)
  * [`mobile/lib/views/reports/tabs/overview_tab.dart`](file:///d:/Isysware%20works/Thrive-Salon-main/mobile/lib/views/reports/tabs/overview_tab.dart)
* **Actions:**
  1. In `drawer_tab.dart`:
     * Read `onlineBreakdown` from `backendDrawerBalances` or calculate from sale payments.
     * Under the "Online Payments" row, add an expandable card / indented list:
       ```
       Online Total:  PKR 1,200
         • JazzCash:   PKR 1,000
         • Meezan Bank:  PKR 200
       ```
  2. In `sales_tab.dart` & `overview_tab.dart`:
     * Display the bank breakdown in the summary cards and sale details popup.
* **Done Criteria:** Reports Drawer Tab clearly lists sub-categories with correct respective amounts.

---

## Step 10: End-to-End Local Verification & Production Build Validation
* **Objective:** Verify the complete flow locally, check for edge cases, and validate production build commands.
* **Target Files:**
  * Entire project (`backend` + `mobile`)
  * [`mobile/CPANEL_DEPLOYMENT.md`](file:///d:/Isysware%20works/Thrive-Salon-main/mobile/CPANEL_DEPLOYMENT.md)
* **Actions:**
  1. **Local Flow Test:**
     * Create 2 accounts in Settings: "JazzCash" and "Meezan Bank".
     * Create Sale 1: Total PKR 1,000 (Paid via JazzCash).
     * Create Sale 2: Total PKR 500 (Split: PKR 300 Meezan, PKR 200 JazzCash).
     * Open Drawer Tab: Verify Total Online = PKR 1,500 (JazzCash: PKR 1,200, Meezan: PKR 300).
  2. **Edge Cases Test:**
     * Legacy sales without account info show under "Other / General Online".
     * Voiding a sale properly reverses the respective bank account's balance.
  3. **Production Validation:**
     * Verify `backend` compiles with `npm run build` (zero errors).
     * Document SQL migration commands in deployment notes for live production roll-out.
* **Done Criteria:** Zero errors in logs, all sub-category amounts match exactly, and production deployment instructions are ready.
