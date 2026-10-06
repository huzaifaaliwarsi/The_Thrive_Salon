import { pgTable, pgEnum, uuid, text, numeric, integer, boolean, date, timestamp } from 'drizzle-orm/pg-core';
import { relations, sql } from 'drizzle-orm';

export const appointmentStatus = pgEnum('appointment_status', ['PENDING',
  'CONFIRMED',
  'COMPLETED',
  'CANCELLED',
  'PENDING_CHECKOUT']);
export const approvalStatus = pgEnum('approval_status', ['PENDING',
  'APPROVED',
  'REJECTED']);
export const attendanceStatus = pgEnum('attendance_status', ['PRESENT',
  'ABSENT',
  'LEAVE',
  'LATE',
  'SUNDAY',
  'HOLIDAY']);
export const salaryType = pgEnum('salary_type', ['MONTHLY',
  'DAILY',
  'COMMISSION',
  'MONTHLY_PLUS_COMMISSION',
  'DAILY_PLUS_COMMISSION']);
export const userRole = pgEnum('user_role', ['SUPER_ADMIN',
  'OWNER',
  'STAFF']);

export const SysConfig = pgTable('_sys_config', {
  key: text('key').primaryKey().notNull(),
  value: text('value').notNull(),
});

export const appointments = pgTable('appointments', {
  id: uuid('id').defaultRandom().primaryKey(),
  salonId: uuid('salon_id'),
  serviceId: uuid('service_id'),
  serviceIds: text('service_ids'),
  serviceDetails: text('service_details'),
  staffId: uuid('staff_id'),
  customerName: text('customer_name').notNull(),
  customerPhone: text('customer_phone'),
  appointmentTime: timestamp('appointment_time').notNull(),
  status: appointmentStatus('status').default(sql`'PENDING'::public.appointment_status`),
  notes: text('notes'),
  createdAt: timestamp('created_at').default(sql`now()`),
});

export const attendance = pgTable('attendance', {
  id: uuid('id').defaultRandom().primaryKey(),
  staffId: uuid('staff_id'),
  salonId: uuid('salon_id'),
  status: attendanceStatus('status').notNull(),
  approvalStatus: approvalStatus('approval_status').notNull().default(sql`'PENDING'::public.approval_status`),
  checkIn: timestamp('check_in'),
  checkOut: timestamp('check_out'),
  earlyExit: boolean('early_exit').default(sql`false`),
  date: date('date').default(sql`CURRENT_DATE`),
  createdAt: timestamp('created_at').default(sql`now()`),
  source: text('source').default(sql`'MANUAL'::text`),
  deviceSn: text('device_sn'),
});

export const attendanceLocks = pgTable('attendance_locks', {
  id: uuid('id').defaultRandom().primaryKey(),
  salonId: uuid('salon_id'),
  date: date('date').notNull(),
  lockedBy: uuid('locked_by'),
  createdAt: timestamp('created_at').default(sql`now()`),
});

export const clients = pgTable('clients', {
  id: uuid('id').defaultRandom().primaryKey(),
  salonId: uuid('salon_id'),
  name: text('name').notNull(),
  phone: text('phone'),
  email: text('email'),
  notes: text('notes'),
  source: text('source').default(sql`'WALK_IN'::text`),
  totalSpent: numeric('total_spent', { precision: 10, scale: 2 }).default(sql`'0'::numeric`),
  balance: numeric('balance', { precision: 10, scale: 2 }).default(sql`'0'::numeric`),
  lastVisit: timestamp('last_visit'),
  createdAt: timestamp('created_at').default(sql`now()`),
});

export const expenses = pgTable('expenses', {
  id: uuid('id').defaultRandom().primaryKey(),
  salonId: uuid('salon_id'),
  name: text('name').notNull(),
  category: text('category').notNull(),
  amount: numeric('amount', { precision: 10, scale: 2 }).notNull(),
  date: date('date').default(sql`CURRENT_DATE`),
  createdAt: timestamp('created_at').default(sql`now()`),
});

export const inventoryItems = pgTable('inventory_items', {
  id: uuid('id').defaultRandom().primaryKey(),
  salonId: uuid('salon_id'),
  vendorId: uuid('vendor_id'),
  name: text('name').notNull(),
  sku: text('sku'),
  stockQuantity: numeric('stock_quantity', { precision: 10, scale: 2 }).default(sql`'0'::numeric`),
  unit: text('unit').notNull(),
  unitPrice: numeric('unit_price', { precision: 10, scale: 2 }).default(sql`'0'::numeric`),
  sellingPrice: numeric('selling_price', { precision: 10, scale: 2 }).default(sql`'0'::numeric`),
  canBeSold: text('can_be_sold').default(sql`'false'::text`),
  expiryDate: date('expiry_date'),
  lowStockThreshold: numeric('low_stock_threshold', { precision: 10, scale: 2 }).default(sql`'5'::numeric`),
  createdAt: timestamp('created_at').default(sql`now()`),
});

export const inventoryTransactions = pgTable('inventory_transactions', {
  id: uuid('id').defaultRandom().primaryKey(),
  itemId: uuid('item_id'),
  salonId: uuid('salon_id'),
  type: text('type').notNull(),
  quantity: numeric('quantity', { precision: 10, scale: 2 }).notNull(),
  date: timestamp('date').default(sql`now()`),
  notes: text('notes'),
  createdAt: timestamp('created_at').default(sql`now()`),
});

export const ledgerEntries = pgTable('ledger_entries', {
  id: uuid('id').defaultRandom().primaryKey(),
  salonId: uuid('salon_id'),
  clientId: uuid('client_id'),
  vendorId: uuid('vendor_id'),
  staffId: uuid('staff_id'),
  saleId: uuid('sale_id'),
  purchaseId: uuid('purchase_id'),
  salaryDeductionId: uuid('salary_deduction_id'),
  expenseId: uuid('expense_id'),
  type: text('type').notNull(),
  amount: numeric('amount', { precision: 10, scale: 2 }).notNull(),
  category: text('category').notNull(),
  notes: text('notes'),
  personName: text('person_name'),
  date: timestamp('date').default(sql`now()`),
  createdAt: timestamp('created_at').default(sql`now()`),
});

export const purchases = pgTable('purchases', {
  id: uuid('id').defaultRandom().primaryKey(),
  salonId: uuid('salon_id'),
  vendorId: uuid('vendor_id'),
  total: numeric('total', { precision: 10, scale: 2 }).notNull(),
  amountPaid: numeric('amount_paid', { precision: 10, scale: 2 }).default(sql`'0'::numeric`),
  paymentMethod: text('payment_method').notNull(),
  date: timestamp('date').default(sql`now()`),
  notes: text('notes'),
  createdAt: timestamp('created_at').default(sql`now()`),
});

export const salaryDeductions = pgTable('salary_deductions', {
  id: uuid('id').defaultRandom().primaryKey(),
  staffId: uuid('staff_id'),
  salonId: uuid('salon_id'),
  type: text('type').notNull(),
  amount: numeric('amount', { precision: 10, scale: 2 }).notNull(),
  reason: text('reason'),
  date: date('date').default(sql`CURRENT_DATE`),
  notedBy: uuid('noted_by'),
  createdAt: timestamp('created_at').default(sql`now()`),
});

export const saleItems = pgTable('sale_items', {
  id: uuid('id').defaultRandom().primaryKey(),
  saleId: uuid('sale_id'),
  serviceId: uuid('service_id'),
  productId: uuid('product_id'),
  staffId: uuid('staff_id'),
  quantity: numeric('quantity').default(sql`'1'::numeric`),
  price: numeric('price', { precision: 10, scale: 2 }).notNull(),
  discountAmount: numeric('discount_amount', { precision: 10, scale: 2 }).default(sql`'0'::numeric`),
  taxAmount: numeric('tax_amount', { precision: 10, scale: 2 }).default(sql`'0'::numeric`),
  commissionAmount: numeric('commission_amount', { precision: 10, scale: 2 }).default(sql`'0'::numeric`),
  isInternal: boolean('is_internal').default(sql`false`),
});

export const sales = pgTable('sales', {
  id: uuid('id').defaultRandom().primaryKey(),
  salonId: uuid('salon_id'),
  staffId: uuid('staff_id'),
  customerPhone: text('customer_phone'),
  customerName: text('customer_name'),
  customerSource: text('customer_source'),
  subtotal: numeric('subtotal', { precision: 10, scale: 2 }).notNull(),
  discount: numeric('discount', { precision: 10, scale: 2 }).default(sql`'0'::numeric`),
  total: numeric('total', { precision: 10, scale: 2 }).notNull(),
  commissionRate: numeric('commission_rate', { precision: 5, scale: 2 }).default(sql`'0'::numeric`),
  taxRate: numeric('tax_rate', { precision: 5, scale: 2 }).default(sql`'0'::numeric`),
  taxAmount: numeric('tax_amount', { precision: 10, scale: 2 }).default(sql`'0'::numeric`),
  status: text('status').default(sql`'ACTIVE'::text`),
  voidReason: text('void_reason'),
  paymentMethod: text('payment_method').notNull(),
  paymentAccountId: uuid('payment_account_id').references(() => paymentAccounts.id),
  paymentBreakdown: text('payment_breakdown'),
  amountPaid: numeric('amount_paid', { precision: 10, scale: 2 }),
  createdAt: timestamp('created_at').default(sql`now()`),
});

export const salons = pgTable('salons', {
  id: uuid('id').defaultRandom().primaryKey(),
  name: text('name').notNull(),
  logo: text('logo'),
  address: text('address'),
  subscriptionEnd: timestamp('subscription_end').default(sql`(now() + '30 days'::interval)`),
  isSuspended: text('is_suspended').default(sql`'false'::text`),
  cashBalance: numeric('cash_balance', { precision: 12, scale: 2 }).default(sql`'0'::numeric`),
  createdAt: timestamp('created_at').default(sql`now()`),
  updatedAt: timestamp('updated_at').default(sql`now()`),
  lateTimeLimit: text('late_time_limit').default(sql`'09:00'::text`),
  timezone: text('timezone').default(sql`'Asia/Karachi'::text`),
  inTimeLimit: text('in_time_limit').default(sql`'09:00'::text`),
  outTimeLimit: text('out_time_limit').default(sql`'18:00'::text`),
  earlyExitTimeLimit: text('early_exit_time_limit').default(sql`'17:45'::text`),
  lateDeductionRate: numeric('late_deduction_rate', { precision: 10, scale: 2 }).default(sql`'10'::numeric`),
  earlyExitDeductionRate: numeric('early_exit_deduction_rate', { precision: 10, scale: 2 }).default(sql`'10'::numeric`),
  vatNumber: text('vat_number'),
  qrDomain: text('qr_domain').default(sql`'salonpro.app'::text`),
  zktecoDeviceSn: text('zkteco_device_sn'),
  zktecoDeviceName: text('zkteco_device_name'),
  zktecoPushToken: text('zkteco_push_token'),
  zktecoLastSync: timestamp('zkteco_last_sync'),
  zktecoEnabled: boolean('zkteco_enabled').default(sql`false`),
});

export const paymentAccounts = pgTable('payment_accounts', {
  id: uuid('id').defaultRandom().primaryKey(),
  salonId: uuid('salon_id').notNull().references(() => salons.id, { onDelete: 'cascade' }),
  accountName: text('account_name').notNull(),
  accountTitle: text('account_title'),
  accountNumber: text('account_number'),
  type: text('type').default(sql`'BANK'::text`),
  isActive: boolean('is_active').default(sql`true`),
  createdAt: timestamp('created_at').default(sql`now()`),
  updatedAt: timestamp('updated_at').default(sql`now()`),
});

export const servicePackageItems = pgTable('service_package_items', {
  id: uuid('id').defaultRandom().primaryKey(),
  packageId: uuid('package_id'),
  serviceId: uuid('service_id'),
  price: numeric('price', { precision: 10, scale: 2 }).default(sql`'0'::numeric`),
});

export const services = pgTable('services', {
  id: uuid('id').defaultRandom().primaryKey(),
  salonId: uuid('salon_id'),
  name: text('name').notNull(),
  price: numeric('price', { precision: 10, scale: 2 }).notNull(),
  category: text('category').notNull(),
  isActive: text('is_active').default(sql`'true'::text`),
  isPackage: text('is_package').default(sql`'false'::text`),
  description: text('description'),
  arabicName: text('arabic_name'),
  createdAt: timestamp('created_at').default(sql`now()`),
});

export const staff = pgTable('staff', {
  id: uuid('id').defaultRandom().primaryKey(),
  userId: uuid('user_id'),
  salonId: uuid('salon_id'),
  name: text('name').notNull(),
  phone: text('phone'),
  salaryType: salaryType('salary_type').notNull(),
  salaryValue: numeric('salary_value', { precision: 10, scale: 2 }),
  commissionPercentage: numeric('commission_percentage', { precision: 5, scale: 2 }).default(sql`'0'::numeric`),
  inTimeLimit: text('in_time_limit').default(sql`'09:00'::text`),
  outTimeLimit: text('out_time_limit').default(sql`'18:00'::text`),
  lateTimeLimit: text('late_time_limit').default(sql`'09:15'::text`),
  earlyExitTimeLimit: text('early_exit_time_limit').default(sql`'17:45'::text`),
  lateDeductionRate: numeric('late_deduction_rate', { precision: 10, scale: 2 }).default(sql`'0'::numeric`),
  earlyExitDeductionRate: numeric('early_exit_deduction_rate', { precision: 10, scale: 2 }).default(sql`'0'::numeric`),
  allowedLeaves: integer('allowed_leaves').default(sql`0`),
  joiningDate: date('joining_date').default(sql`CURRENT_DATE`),
  createdAt: timestamp('created_at').default(sql`now()`),
  biometricPin: text('biometric_pin'),
});

export const staffSalaryHistory = pgTable('staff_salary_history', {
  id: uuid('id').defaultRandom().primaryKey(),
  staffId: uuid('staff_id'),
  salonId: uuid('salon_id'),
  salaryType: salaryType('salary_type').notNull(),
  salaryValue: numeric('salary_value', { precision: 10, scale: 2 }),
  commissionPercentage: numeric('commission_percentage', { precision: 5, scale: 2 }).default(sql`'0'::numeric`),
  effectiveDate: date('effective_date').notNull(),
  createdAt: timestamp('created_at').default(sql`now()`),
});

export const users = pgTable('users', {
  id: uuid('id').defaultRandom().primaryKey(),
  email: text('email').notNull(),
  phone: text('phone'),
  password: text('password').notNull(),
  plainPassword: text('plain_password'),
  role: userRole('role').notNull(),
  salonId: uuid('salon_id'),
  name: text('name'),
  isActive: text('is_active').default(sql`'true'::text`),
  createdAt: timestamp('created_at').default(sql`now()`),
});

export const vendors = pgTable('vendors', {
  id: uuid('id').defaultRandom().primaryKey(),
  salonId: uuid('salon_id'),
  name: text('name').notNull(),
  contactPerson: text('contact_person'),
  phone: text('phone'),
  email: text('email'),
  address: text('address'),
  balance: numeric('balance', { precision: 10, scale: 2 }).default(sql`'0'::numeric`),
  createdAt: timestamp('created_at').default(sql`now()`),
});

export const appointmentsRelations = relations(appointments, ({ one, many }) => ({
  salon: one(salons, { fields: [appointments.salonId], references: [salons.id], relationName: 'appointments_salon_id' }),
  service: one(services, { fields: [appointments.serviceId], references: [services.id], relationName: 'appointments_service_id' }),
  staff: one(staff, { fields: [appointments.staffId], references: [staff.id], relationName: 'appointments_staff_id' })
}));

export const attendanceRelations = relations(attendance, ({ one, many }) => ({
  salon: one(salons, { fields: [attendance.salonId], references: [salons.id], relationName: 'attendance_salon_id' }),
  staff: one(staff, { fields: [attendance.staffId], references: [staff.id], relationName: 'attendance_staff_id' })
}));

export const attendanceLocksRelations = relations(attendanceLocks, ({ one, many }) => ({
  lockedByUser: one(users, { fields: [attendanceLocks.lockedBy], references: [users.id], relationName: 'attendance_locks_locked_by' }),
  salon: one(salons, { fields: [attendanceLocks.salonId], references: [salons.id], relationName: 'attendance_locks_salon_id' })
}));

export const clientsRelations = relations(clients, ({ one, many }) => ({
  salon: one(salons, { fields: [clients.salonId], references: [salons.id], relationName: 'clients_salon_id' }),
  ledgerEntries: many(ledgerEntries, { relationName: 'ledger_entries_client_id' })
}));

export const expensesRelations = relations(expenses, ({ one, many }) => ({
  salon: one(salons, { fields: [expenses.salonId], references: [salons.id], relationName: 'expenses_salon_id' }),
  ledgerEntries: many(ledgerEntries, { relationName: 'ledger_entries_expense_id' })
}));

export const inventoryItemsRelations = relations(inventoryItems, ({ one, many }) => ({
  salon: one(salons, { fields: [inventoryItems.salonId], references: [salons.id], relationName: 'inventory_items_salon_id' }),
  vendor: one(vendors, { fields: [inventoryItems.vendorId], references: [vendors.id], relationName: 'inventory_items_vendor_id' }),
  inventoryTransactions: many(inventoryTransactions, { relationName: 'inventory_transactions_item_id' }),
  saleItems: many(saleItems, { relationName: 'sale_items_product_id' })
}));

export const inventoryTransactionsRelations = relations(inventoryTransactions, ({ one, many }) => ({
  item: one(inventoryItems, { fields: [inventoryTransactions.itemId], references: [inventoryItems.id], relationName: 'inventory_transactions_item_id' }),
  salon: one(salons, { fields: [inventoryTransactions.salonId], references: [salons.id], relationName: 'inventory_transactions_salon_id' })
}));

export const ledgerEntriesRelations = relations(ledgerEntries, ({ one, many }) => ({
  client: one(clients, { fields: [ledgerEntries.clientId], references: [clients.id], relationName: 'ledger_entries_client_id' }),
  expense: one(expenses, { fields: [ledgerEntries.expenseId], references: [expenses.id], relationName: 'ledger_entries_expense_id' }),
  purchase: one(purchases, { fields: [ledgerEntries.purchaseId], references: [purchases.id], relationName: 'ledger_entries_purchase_id' }),
  salaryDeduction: one(salaryDeductions, { fields: [ledgerEntries.salaryDeductionId], references: [salaryDeductions.id], relationName: 'ledger_entries_salary_deduction_id' }),
  sale: one(sales, { fields: [ledgerEntries.saleId], references: [sales.id], relationName: 'ledger_entries_sale_id' }),
  salon: one(salons, { fields: [ledgerEntries.salonId], references: [salons.id], relationName: 'ledger_entries_salon_id' }),
  staff: one(staff, { fields: [ledgerEntries.staffId], references: [staff.id], relationName: 'ledger_entries_staff_id' }),
  vendor: one(vendors, { fields: [ledgerEntries.vendorId], references: [vendors.id], relationName: 'ledger_entries_vendor_id' })
}));

export const purchasesRelations = relations(purchases, ({ one, many }) => ({
  ledgerEntries: many(ledgerEntries, { relationName: 'ledger_entries_purchase_id' }),
  salon: one(salons, { fields: [purchases.salonId], references: [salons.id], relationName: 'purchases_salon_id' }),
  vendor: one(vendors, { fields: [purchases.vendorId], references: [vendors.id], relationName: 'purchases_vendor_id' })
}));

export const salaryDeductionsRelations = relations(salaryDeductions, ({ one, many }) => ({
  ledgerEntries: many(ledgerEntries, { relationName: 'ledger_entries_salary_deduction_id' }),
  notedByUser: one(users, { fields: [salaryDeductions.notedBy], references: [users.id], relationName: 'salary_deductions_noted_by' }),
  salon: one(salons, { fields: [salaryDeductions.salonId], references: [salons.id], relationName: 'salary_deductions_salon_id' }),
  staff: one(staff, { fields: [salaryDeductions.staffId], references: [staff.id], relationName: 'salary_deductions_staff_id' })
}));

export const saleItemsRelations = relations(saleItems, ({ one, many }) => ({
  product: one(inventoryItems, { fields: [saleItems.productId], references: [inventoryItems.id], relationName: 'sale_items_product_id' }),
  sale: one(sales, { fields: [saleItems.saleId], references: [sales.id], relationName: 'sale_items_sale_id' }),
  service: one(services, { fields: [saleItems.serviceId], references: [services.id], relationName: 'sale_items_service_id' }),
  staff: one(staff, { fields: [saleItems.staffId], references: [staff.id], relationName: 'sale_items_staff_id' })
}));

export const paymentAccountsRelations = relations(paymentAccounts, ({ one, many }) => ({
  salon: one(salons, { fields: [paymentAccounts.salonId], references: [salons.id], relationName: 'payment_accounts_salon_id' }),
  sales: many(sales, { relationName: 'sales_payment_account_id' }),
}));


export const salesRelations = relations(sales, ({ one, many }) => ({
  ledgerEntries: many(ledgerEntries, { relationName: 'ledger_entries_sale_id' }),
  saleItems: many(saleItems, { relationName: 'sale_items_sale_id' }),
  salon: one(salons, { fields: [sales.salonId], references: [salons.id], relationName: 'sales_salon_id' }),
  staff: one(staff, { fields: [sales.staffId], references: [staff.id], relationName: 'sales_staff_id' }),
  paymentAccount: one(paymentAccounts, { fields: [sales.paymentAccountId], references: [paymentAccounts.id], relationName: 'sales_payment_account_id' }),
}));

export const salonsRelations = relations(salons, ({ one, many }) => ({
  appointments: many(appointments, { relationName: 'appointments_salon_id' }),
  attendanceLocks: many(attendanceLocks, { relationName: 'attendance_locks_salon_id' }),
  attendance: many(attendance, { relationName: 'attendance_salon_id' }),
  clients: many(clients, { relationName: 'clients_salon_id' }),
  expenses: many(expenses, { relationName: 'expenses_salon_id' }),
  inventoryItems: many(inventoryItems, { relationName: 'inventory_items_salon_id' }),
  inventoryTransactions: many(inventoryTransactions, { relationName: 'inventory_transactions_salon_id' }),
  ledgerEntries: many(ledgerEntries, { relationName: 'ledger_entries_salon_id' }),
  paymentAccounts: many(paymentAccounts, { relationName: 'payment_accounts_salon_id' }),
  purchases: many(purchases, { relationName: 'purchases_salon_id' }),
  salaryDeductions: many(salaryDeductions, { relationName: 'salary_deductions_salon_id' }),
  sales: many(sales, { relationName: 'sales_salon_id' }),
  services: many(services, { relationName: 'services_salon_id' }),
  staffSalaryHistory: many(staffSalaryHistory, { relationName: 'staff_salary_history_salon_id' }),
  staff: many(staff, { relationName: 'staff_salon_id' }),
  users: many(users, { relationName: 'users_salon_id' }),
  vendors: many(vendors, { relationName: 'vendors_salon_id' })
}));

export const servicePackageItemsRelations = relations(servicePackageItems, ({ one, many }) => ({
  package: one(services, { fields: [servicePackageItems.packageId], references: [services.id], relationName: 'service_package_items_package_id' }),
  service: one(services, { fields: [servicePackageItems.serviceId], references: [services.id], relationName: 'service_package_items_service_id' })
}));

export const servicesRelations = relations(services, ({ one, many }) => ({
  appointments: many(appointments, { relationName: 'appointments_service_id' }),
  saleItems: many(saleItems, { relationName: 'sale_items_service_id' }),
  bundleItems: many(servicePackageItems, { relationName: 'service_package_items_package_id' }),
  packageMemberships: many(servicePackageItems, { relationName: 'service_package_items_service_id' }),
  salon: one(salons, { fields: [services.salonId], references: [salons.id], relationName: 'services_salon_id' })
}));

export const staffRelations = relations(staff, ({ one, many }) => ({
  appointments: many(appointments, { relationName: 'appointments_staff_id' }),
  attendance: many(attendance, { relationName: 'attendance_staff_id' }),
  ledgerEntries: many(ledgerEntries, { relationName: 'ledger_entries_staff_id' }),
  salaryDeductions: many(salaryDeductions, { relationName: 'salary_deductions_staff_id' }),
  saleItems: many(saleItems, { relationName: 'sale_items_staff_id' }),
  sales: many(sales, { relationName: 'sales_staff_id' }),
  staffSalaryHistory: many(staffSalaryHistory, { relationName: 'staff_salary_history_staff_id' }),
  salon: one(salons, { fields: [staff.salonId], references: [salons.id], relationName: 'staff_salon_id' }),
  user: one(users, { fields: [staff.userId], references: [users.id], relationName: 'staff_user_id' })
}));

export const staffSalaryHistoryRelations = relations(staffSalaryHistory, ({ one, many }) => ({
  salon: one(salons, { fields: [staffSalaryHistory.salonId], references: [salons.id], relationName: 'staff_salary_history_salon_id' }),
  staff: one(staff, { fields: [staffSalaryHistory.staffId], references: [staff.id], relationName: 'staff_salary_history_staff_id' })
}));

export const usersRelations = relations(users, ({ one, many }) => ({
  attendanceLocks: many(attendanceLocks, { relationName: 'attendance_locks_locked_by' }),
  salaryDeductions: many(salaryDeductions, { relationName: 'salary_deductions_noted_by' }),
  staff: many(staff, { relationName: 'staff_user_id' }),
  salon: one(salons, { fields: [users.salonId], references: [salons.id], relationName: 'users_salon_id' })
}));

export const vendorsRelations = relations(vendors, ({ one, many }) => ({
  inventoryItems: many(inventoryItems, { relationName: 'inventory_items_vendor_id' }),
  ledgerEntries: many(ledgerEntries, { relationName: 'ledger_entries_vendor_id' }),
  purchases: many(purchases, { relationName: 'purchases_vendor_id' }),
  salon: one(salons, { fields: [vendors.salonId], references: [salons.id], relationName: 'vendors_salon_id' })
}));
