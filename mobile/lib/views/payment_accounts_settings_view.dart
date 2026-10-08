import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../models/payment_account.dart';
import '../../providers/payment_accounts_provider.dart';

class PaymentAccountsSettingsView extends ConsumerStatefulWidget {
  const PaymentAccountsSettingsView({super.key});

  @override
  ConsumerState<PaymentAccountsSettingsView> createState() => _PaymentAccountsSettingsViewState();
}

class _PaymentAccountsSettingsViewState extends ConsumerState<PaymentAccountsSettingsView> {
  bool _includeInactive = true;

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(paymentAccountsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Payment Accounts',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF1E293B),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            onPressed: () => ref.read(paymentAccountsProvider.notifier).fetchAccounts(includeInactive: _includeInactive),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF8B5CF6),
        icon: const Icon(LucideIcons.plus, color: Colors.white, size: 20),
        label: Text(
          'Add Account',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        onPressed: () => _showAccountDialog(context),
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6))),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.alertCircle, color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              Text('Failed to load accounts', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 6),
              Text(err.toString(), style: GoogleFonts.outfit(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.read(paymentAccountsProvider.notifier).fetchAccounts(),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
                child: Text('Retry', style: GoogleFonts.outfit(color: Colors.white)),
              ),
            ],
          ),
        ),
        data: (accounts) {
          final displayAccounts = _includeInactive ? accounts : accounts.where((a) => a.isActive).toList();

          if (displayAccounts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.landmark, color: Color(0xFF8B5CF6), size: 48),
                  ),
                  const SizedBox(height: 16),
                  Text('No Payment Accounts Configured', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text('Add your salon bank accounts and digital wallets for online payments.', style: GoogleFonts.outfit(fontSize: 13, color: Colors.black54)),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(LucideIcons.plus, size: 18, color: Colors.white),
                    label: Text('Add First Account', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
                    onPressed: () => _showAccountDialog(context),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Configured Accounts (${displayAccounts.length})',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B)),
                    ),
                    Row(
                      children: [
                        Text('Show Inactive', style: GoogleFonts.outfit(fontSize: 12, color: Colors.black54)),
                        const SizedBox(width: 4),
                        Switch(
                          value: _includeInactive,
                          activeThumbColor: const Color(0xFF8B5CF6),
                          onChanged: (val) {
                            setState(() => _includeInactive = val);
                            ref.read(paymentAccountsProvider.notifier).fetchAccounts(includeInactive: val);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...displayAccounts.map((account) => _buildAccountCard(account)),
                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAccountCard(PaymentAccount account) {
    final isBank = account.type.toUpperCase() == 'BANK';
    final isWallet = account.type.toUpperCase() == 'WALLET';

    final IconData typeIcon = isBank
        ? LucideIcons.landmark
        : isWallet
            ? LucideIcons.wallet
            : LucideIcons.creditCard;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: account.isActive ? const Color(0xFFE2E8F0) : Colors.black12,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: account.isActive
                      ? const Color(0xFF8B5CF6).withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  typeIcon,
                  color: account.isActive ? const Color(0xFF8B5CF6) : Colors.grey,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            account.accountName,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: account.isActive ? const Color(0xFF1E293B) : Colors.black45,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            account.type,
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF8B5CF6),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (account.accountTitle != null && account.accountTitle!.isNotEmpty)
                      Text(
                        account.accountTitle!,
                        style: GoogleFonts.outfit(fontSize: 13, color: Colors.black54),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: account.isActive
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: account.isActive ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      account.isActive ? 'Active' : 'Inactive',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: account.isActive ? Colors.green : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Account / Mobile Number', style: GoogleFonts.outfit(fontSize: 10, color: Colors.black45, fontWeight: FontWeight.w500)),
                    Text(
                      account.accountNumber?.isNotEmpty == true ? account.accountNumber! : 'Not Set',
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                    ),
                  ],
                ),
              ),
              if (account.iban != null && account.iban!.isNotEmpty)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('IBAN', style: GoogleFonts.outfit(fontSize: 10, color: Colors.black45, fontWeight: FontWeight.w500)),
                      Text(
                        account.iban!,
                        style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(LucideIcons.edit2, size: 14),
                label: Text('Edit', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13)),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF8B5CF6)),
                onPressed: () => _showAccountDialog(context, account: account),
              ),
              const SizedBox(width: 8),
              if (account.isActive)
                TextButton.icon(
                  icon: const Icon(LucideIcons.power, size: 14),
                  label: Text('Deactivate', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13)),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFFD97706)),
                  onPressed: () => _confirmDeactivate(account),
                )
              else
                TextButton.icon(
                  icon: const Icon(LucideIcons.checkCircle, size: 14),
                  label: Text('Activate', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13)),
                  style: TextButton.styleFrom(foregroundColor: Colors.green),
                  onPressed: () => _activateAccount(account),
                ),
              const SizedBox(width: 8),
              TextButton.icon(
                icon: const Icon(LucideIcons.trash2, size: 14),
                label: Text('Delete', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13)),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                onPressed: () => _confirmDelete(account),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAccountDialog(BuildContext context, {PaymentAccount? account}) {
    final isEditing = account != null;
    final nameCtrl = TextEditingController(text: account?.accountName ?? '');
    final titleCtrl = TextEditingController(text: account?.accountTitle ?? '');
    final numberCtrl = TextEditingController(text: account?.accountNumber ?? '');
    final ibanCtrl = TextEditingController(text: account?.iban ?? '');
    String selectedType = account?.type ?? 'BANK';
    bool isActive = account?.isActive ?? true;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(
                isEditing ? LucideIcons.edit3 : LucideIcons.plusCircle,
                color: const Color(0xFF8B5CF6),
              ),
              const SizedBox(width: 10),
              Text(
                isEditing ? 'Edit Payment Account' : 'New Payment Account',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Account Name *',
                      hintText: 'e.g. Meezan Bank, JazzCash, EasyPaisa',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(LucideIcons.tag, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: 'Account Title',
                      hintText: 'e.g. The Thrive Salon',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(LucideIcons.user, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: numberCtrl,
                    decoration: InputDecoration(
                      labelText: 'Account / Mobile Number',
                      hintText: 'e.g. 03001234567 or 010203040506',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(LucideIcons.hash, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ibanCtrl,
                    decoration: InputDecoration(
                      labelText: 'IBAN (Optional)',
                      hintText: 'e.g. PK36MEZN0001020304050607',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(LucideIcons.fileText, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: InputDecoration(
                      labelText: 'Account Type',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(LucideIcons.layers, size: 18),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'BANK', child: Text('Bank Account')),
                      DropdownMenuItem(value: 'WALLET', child: Text('Digital Wallet (JazzCash / EasyPaisa)')),
                      DropdownMenuItem(value: 'POS_MACHINE', child: Text('POS Card Machine')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedType = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: Text('Account Active', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text('Show as selectable payment method at POS checkout', style: GoogleFonts.outfit(fontSize: 11)),
                    value: isActive,
                    activeThumbColor: const Color(0xFF8B5CF6),
                    onChanged: (val) => setDialogState(() => isActive = val),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (isEditing)
              TextButton.icon(
                icon: const Icon(LucideIcons.trash2, size: 14, color: Colors.redAccent),
                label: Text('Delete', style: GoogleFonts.outfit(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  _confirmDelete(account);
                },
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text('Cancel', style: GoogleFonts.outfit()),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Account name is required')),
                  );
                  return;
                }

                final payload = {
                  'accountName': name,
                  'accountTitle': titleCtrl.text.trim().isNotEmpty ? titleCtrl.text.trim() : null,
                  'accountNumber': numberCtrl.text.trim().isNotEmpty ? numberCtrl.text.trim() : null,
                  'iban': ibanCtrl.text.trim().isNotEmpty ? ibanCtrl.text.trim().toUpperCase() : null,
                  'type': selectedType,
                  'isActive': isActive,
                };

                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(dialogCtx);

                try {
                  if (isEditing) {
                    await ref.read(paymentAccountsProvider.notifier).updateAccount(account.id, payload);
                  } else {
                    await ref.read(paymentAccountsProvider.notifier).createAccount(payload);
                  }
                  navigator.pop();
                  messenger.showSnackBar(
                    SnackBar(content: Text(isEditing ? 'Account updated successfully' : 'Account created successfully')),
                  );
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text(e.toString())));
                }
              },
              child: Text(
                isEditing ? 'Update Account' : 'Save Account',
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeactivate(PaymentAccount account) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(LucideIcons.alertTriangle, color: Color(0xFFD97706)),
            const SizedBox(width: 10),
            Text('Deactivate Account?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Deactivating "${account.accountName}" will hide it from the POS checkout. Historical sales and ledger records will be preserved.',
          style: GoogleFonts.outfit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(dialogCtx);
              try {
                await ref.read(paymentAccountsProvider.notifier).deleteAccount(account.id, permanent: false);
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text('Account "${account.accountName}" deactivated')),
                );
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            child: Text('Deactivate', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(PaymentAccount account) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(LucideIcons.trash2, color: Colors.redAccent),
            const SizedBox(width: 10),
            Text('Delete Account?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete "${account.accountName}"? This action cannot be undone.',
          style: GoogleFonts.outfit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(dialogCtx);
              try {
                await ref.read(paymentAccountsProvider.notifier).deleteAccount(account.id, permanent: true);
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text('Account "${account.accountName}" deleted permanently')),
                );
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            child: Text('Delete', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _activateAccount(PaymentAccount account) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(paymentAccountsProvider.notifier).updateAccount(account.id, {'isActive': true});
      messenger.showSnackBar(
        SnackBar(content: Text('Account "${account.accountName}" activated')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}
