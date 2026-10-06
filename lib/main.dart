import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appStore.initStorage();
  runApp(const PopInvoiceApp());
}

// ---------------- DATA MODELS ----------------
class Product {
  final int id;
  String name;
  String icon;
  String category;
  double price;
  String? image; // base64 picture (optional)

  Product({
    required this.id,
    required this.name,
    required this.icon,
    required this.category,
    required this.price,
    this.image,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'icon': icon,
        'category': category,
        'price': price,
        'image': image,
      };

  // Without picture (used inside invoices to keep storage small)
  Map<String, dynamic> toLightMap() => {
        'id': id,
        'name': name,
        'icon': icon,
        'category': category,
        'price': price,
      };

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'],
        name: map['name'],
        icon: map['icon'],
        category: map['category'],
        price: (map['price'] as num).toDouble(),
        image: map['image'] as String?,
      );
}

// Shows product picture if available, otherwise the emoji icon
class ProductThumb extends StatelessWidget {
  final Product product;
  final double size;
  const ProductThumb({super.key, required this.product, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final img = product.image;
    if (img != null && img.isNotEmpty) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            base64Decode(img),
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => Icon(Icons.image_not_supported, size: size * 0.7),
          ),
        );
      } catch (_) {}
    }
    return SizedBox(
      width: size,
      height: size,
      child: Center(child: Text(product.icon, style: TextStyle(fontSize: size * 0.7))),
    );
  }
}

class InvoiceItem {
  final Product product;
  double qty;
  double rate;

  InvoiceItem({
    required this.product,
    required this.qty,
    required this.rate,
  });

  double get total => qty * rate;

  Map<String, dynamic> toMap() => {
        'product': product.toLightMap(),
        'qty': qty,
        'rate': rate,
      };

  factory InvoiceItem.fromMap(Map<String, dynamic> map) => InvoiceItem(
        product: Product.fromMap(map['product']),
        qty: (map['qty'] as num).toDouble(),
        rate: (map['rate'] as num).toDouble(),
      );
}

class Invoice {
  final String invNumber;
  final String date;
  final String customerName;
  final String customerPhone;
  final List<InvoiceItem> items;
  final double subtotal;
  final double discount;
  final double grand;
  final double paid;
  final double previousDue;
  final double remaining;
  final String paymentMethod;
  bool synced;

  Invoice({
    required this.invNumber,
    required this.date,
    required this.customerName,
    required this.customerPhone,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.grand,
    required this.paid,
    required this.previousDue,
    required this.remaining,
    required this.paymentMethod,
    this.synced = false,
  });

  Map<String, dynamic> toMap() => {
        'invNumber': invNumber,
        'date': date,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'items': items.map((i) => i.toMap()).toList(),
        'subtotal': subtotal,
        'discount': discount,
        'grand': grand,
        'paid': paid,
        'previousDue': previousDue,
        'remaining': remaining,
        'paymentMethod': paymentMethod,
        'synced': synced ? 1 : 0,
      };

  factory Invoice.fromMap(Map<String, dynamic> map) => Invoice(
        invNumber: map['invNumber'],
        date: map['date'],
        customerName: map['customerName'],
        customerPhone: map['customerPhone'] ?? '',
        items: (map['items'] as List).map((i) => InvoiceItem.fromMap(i)).toList(),
        subtotal: (map['subtotal'] as num).toDouble(),
        discount: (map['discount'] as num).toDouble(),
        grand: (map['grand'] as num).toDouble(),
        paid: (map['paid'] as num).toDouble(),
        previousDue: (map['previousDue'] as num).toDouble(),
        remaining: (map['remaining'] as num).toDouble(),
        paymentMethod: map['paymentMethod'],
        synced: (map['synced'] ?? 0) == 1,
      );

  String toThermalReceiptText(ShopSettings shop) {
    final sb = StringBuffer();
    const w = 32;

    String center(String text) {
      if (text.length >= w) return text.substring(0, w);
      int left = (w - text.length) ~/ 2;
      return ' ' * left + text;
    }

    String row(String left, String right) {
      int space = w - left.length - right.length;
      if (space < 1) space = 1;
      return left + (' ' * space) + right;
    }

    sb.writeln(center(shop.name.toUpperCase()));
    if (shop.tagline.isNotEmpty) sb.writeln(center(shop.tagline));
    if (shop.phone.isNotEmpty) sb.writeln(center('Ph: ${shop.phone}'));
    if (shop.address.isNotEmpty) sb.writeln(center(shop.address));
    sb.writeln('-' * w);
    sb.writeln(row('Bill: $invNumber', date.length >= 10 ? date.substring(0, 10) : date));
    sb.writeln('Customer: $customerName');
    if (customerPhone.isNotEmpty) sb.writeln('Phone: $customerPhone');
    sb.writeln('=' * w);
    sb.writeln(row('ITEM [QTY x RATE]', 'TOTAL'));
    sb.writeln('-' * w);

    for (var item in items) {
      String itemName = item.product.name;
      if (itemName.length > 20) itemName = itemName.substring(0, 20);
      sb.writeln(itemName);
      String qtyRate = ' ${item.qty.toStringAsFixed(0)} x ${item.rate.toStringAsFixed(0)}';
      String lineTotal = 'Rs.${item.total.toStringAsFixed(0)}';
      sb.writeln(row(qtyRate, lineTotal));
    }

    sb.writeln('-' * w);
    sb.writeln(row('Subtotal:', 'Rs. ${subtotal.toStringAsFixed(0)}'));
    if (discount > 0) sb.writeln(row('Discount:', '-Rs. ${discount.toStringAsFixed(0)}'));
    if (previousDue > 0) sb.writeln(row('Prev Due:', 'Rs. ${previousDue.toStringAsFixed(0)}'));
    sb.writeln(row('Net Payable:', 'Rs. ${(grand + previousDue).toStringAsFixed(0)}'));
    sb.writeln(row('Paid Cash:', 'Rs. ${paid.toStringAsFixed(0)}'));
    if (remaining > 0) sb.writeln(row('Remaining Udhar:', 'Rs. ${remaining.toStringAsFixed(0)}'));
    sb.writeln('=' * w);
    sb.writeln(center('THANK YOU FOR YOUR VISIT!'));
    sb.writeln(center('Software by POP Invoice'));
    sb.writeln('\n\n');

    return sb.toString();
  }
}

class Customer {
  final String key;
  final String name;
  final String phone;
  double balance;

  Customer({
    required this.key,
    required this.name,
    required this.phone,
    required this.balance,
  });

  Map<String, dynamic> toMap() => {
        'key': key,
        'name': name,
        'phone': phone,
        'balance': balance,
      };

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
        key: map['key'],
        name: map['name'],
        phone: map['phone'] ?? '',
        balance: (map['balance'] as num).toDouble(),
      );
}

class ShopSettings {
  String name;
  String tagline;
  String phone;
  String address;
  String syncUrl;

  ShopSettings({
    this.name = 'POP WORKSHOP',
    this.tagline = 'Plaster & False Ceiling Works',
    this.phone = '0300-1234567',
    this.address = 'Main Workshop Market',
    this.syncUrl = '',
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'tagline': tagline,
        'phone': phone,
        'address': address,
        'syncUrl': syncUrl,
      };

  factory ShopSettings.fromMap(Map<String, dynamic> map) => ShopSettings(
        name: map['name'] ?? 'POP WORKSHOP',
        tagline: map['tagline'] ?? '',
        phone: map['phone'] ?? '',
        address: map['address'] ?? '',
        syncUrl: map['syncUrl'] ?? '',
      );
}

// ---------------- PERMANENT PERSISTENT STORE ----------------
class WorkshopStore extends ChangeNotifier {
  ShopSettings shopSettings = ShopSettings();
  List<Product> products = [];
  List<Invoice> invoices = [];
  Map<String, Customer> customers = {};
  bool isSyncing = false;
  String lastSyncDebug = '';

  SharedPreferences? _prefs;

  Future<void> initStorage() async {
    _prefs = await SharedPreferences.getInstance();

    final settingsStr = _prefs?.getString('shop_settings');
    if (settingsStr != null) {
      shopSettings = ShopSettings.fromMap(jsonDecode(settingsStr));
    }

    // Products: clean slate (no default preloaded items)
    final productsStr = _prefs?.getString('products_list');
    if (productsStr != null) {
      final List decoded = jsonDecode(productsStr);
      products = decoded.map((m) => Product.fromMap(m)).toList();
    } else {
      products = [];
    }

    final invoicesStr = _prefs?.getString('invoices_list');
    if (invoicesStr != null) {
      final List decoded = jsonDecode(invoicesStr);
      invoices = decoded.map((m) => Invoice.fromMap(m)).toList();
    }

    final customersStr = _prefs?.getString('customers_map');
    if (customersStr != null) {
      final Map<String, dynamic> decoded = jsonDecode(customersStr);
      customers = decoded.map((k, v) => MapEntry(k, Customer.fromMap(v)));
    }
  }

  void _saveProducts() {
    _prefs?.setString('products_list', jsonEncode(products.map((p) => p.toMap()).toList()));
  }

  void _saveInvoices() {
    _prefs?.setString('invoices_list', jsonEncode(invoices.map((i) => i.toMap()).toList()));
  }

  void _saveCustomers() {
    _prefs?.setString('customers_map', jsonEncode(customers.map((k, v) => MapEntry(k, v.toMap()))));
  }

  String getNextInvoiceNumber() {
    int next = invoices.length + 1;
    return 'INV-${next.toString().padLeft(6, '0')}';
  }

  void updateShopSettings({
    required String name,
    required String tagline,
    required String phone,
    required String address,
    required String syncUrl,
  }) {
    shopSettings = ShopSettings(name: name, tagline: tagline, phone: phone, address: address, syncUrl: syncUrl);
    _prefs?.setString('shop_settings', jsonEncode(shopSettings.toMap()));
    notifyListeners();
  }

  void addProduct(String name, String icon, String category, double price, {String? image}) {
    products.add(Product(
      id: DateTime.now().millisecondsSinceEpoch,
      name: name,
      icon: icon,
      category: category,
      price: price,
      image: image,
    ));
    _saveProducts();
    notifyListeners();
  }

  void editProduct(int id, String newName, String newIcon, String newCategory, double newPrice, {String? image}) {
    final idx = products.indexWhere((p) => p.id == id);
    if (idx != -1) {
      products[idx].name = newName;
      products[idx].icon = newIcon;
      products[idx].category = newCategory;
      products[idx].price = newPrice;
      products[idx].image = image;
      _saveProducts();
      notifyListeners();
    }
  }

  void deleteProduct(int id) {
    products.removeWhere((p) => p.id == id);
    _saveProducts();
    notifyListeners();
  }

  void saveInvoice(Invoice inv) {
    invoices.insert(0, inv);
    if (inv.customerName != 'Walk-in Customer') {
      final key = inv.customerPhone.isNotEmpty ? inv.customerPhone : inv.customerName;
      if (!customers.containsKey(key)) {
        customers[key] = Customer(key: key, name: inv.customerName, phone: inv.customerPhone, balance: 0);
      }
      customers[key]!.balance += inv.remaining;
      _saveCustomers();
    }
    _saveInvoices();
    notifyListeners();

    // Trigger background sync if URL is set
    syncPendingInvoices();
  }

  Future<int> syncPendingInvoices() async {
    if (shopSettings.syncUrl.isEmpty) return 0;
    isSyncing = true;
    notifyListeners();

    int count = 0;
    lastSyncDebug = '';
    final url = Uri.parse(shopSettings.syncUrl.trim());

    for (var inv in invoices.where((i) => !i.synced)) {
      try {
        final payload = {
          'action': 'save_invoice',
          'invNumber': inv.invNumber,
          'date': inv.date,
          'customerName': inv.customerName,
          'customerPhone': inv.customerPhone,
          'subtotal': inv.subtotal,
          'discount': inv.discount,
          'grand': inv.grand,
          'paid': inv.paid,
          'previousDue': inv.previousDue,
          'remaining': inv.remaining,
          'paymentMethod': inv.paymentMethod,
          'receiptText': inv.toThermalReceiptText(shopSettings),
          'items': inv.items.map((i) => {
                'name': i.product.name,
                'qty': i.qty,
                'rate': i.rate,
                'total': i.total,
              }).toList(),
        };

        final resp = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );

        final loc = resp.headers['location'] ?? '';
        final ok = resp.statusCode == 200 ||
            ((resp.statusCode == 302 || resp.statusCode == 303) &&
                loc.contains('googleusercontent.com'));

        if (ok) {
          inv.synced = true;
          count++;
        } else {
          final body = resp.body.length > 120 ? resp.body.substring(0, 120) : resp.body;
          lastSyncDebug = 'Status ${resp.statusCode}\nLocation: $loc\n$body';
        }
      } catch (e) {
        lastSyncDebug = 'Error: $e';
      }
    }

    _saveInvoices();
    isSyncing = false;
    notifyListeners();
    return count;
  }

  void recordPayment(String key, double amount) {
    if (customers.containsKey(key)) {
      customers[key]!.balance -= amount;
      if (customers[key]!.balance < 0) customers[key]!.balance = 0;
      _saveCustomers();
      notifyListeners();
    }
  }

  int get pendingSyncCount => invoices.where((i) => !i.synced).length;

  double get todayCashSales {
    final today = DateTime.now().toString().substring(0, 10);
    return invoices.where((i) => i.date.startsWith(today)).fold(0.0, (sum, i) => sum + i.paid);
  }

  double get todayCreditSales {
    final today = DateTime.now().toString().substring(0, 10);
    return invoices.where((i) => i.date.startsWith(today)).fold(0.0, (sum, i) => sum + i.remaining);
  }
}

final appStore = WorkshopStore();

// ---------------- APP ROOT ----------------
class PopInvoiceApp extends StatelessWidget {
  const PopInvoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'POP Invoice',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6F9),
      ),
      home: const HomeScreen(),
    );
  }
}

// ---------------- 1. HOME SCREEN ----------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    appStore.addListener(_refresh);
  }

  @override
  void dispose() {
    appStore.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().toString().substring(0, 10);
    final todayCount = appStore.invoices.where((i) => i.date.startsWith(today)).length;
    final pendingSync = appStore.pendingSyncCount;

    return Scaffold(
      appBar: AppBar(
        title: Text(appStore.shopSettings.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        actions: [
          if (appStore.shopSettings.syncUrl.isNotEmpty)
            IconButton(
              icon: appStore.isSyncing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Badge(
                      label: Text('$pendingSync'),
                      isLabelVisible: pendingSync > 0,
                      child: const Icon(Icons.cloud_sync),
                    ),
              tooltip: 'Sync with Google Drive/Sheets',
              onPressed: appStore.isSyncing
                  ? null
                  : () async {
                      int count = await appStore.syncPendingInvoices();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            duration: Duration(seconds: count > 0 ? 3 : 20),
                            content: Text(count > 0
                                ? '$count bills synced successfully!'
                                : (appStore.lastSyncDebug.isNotEmpty
                                    ? appStore.lastSyncDebug
                                    : 'No new bills to sync.')),
                            backgroundColor: count > 0 ? Colors.green : Colors.grey.shade800,
                          ),
                        );
                      }
                    },
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Shop Settings',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Today's Overview", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Chip(label: Text('$todayCount Bills'), backgroundColor: Colors.blue.shade50),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _metricTile('Cash Received', 'Rs. ${appStore.todayCashSales.toStringAsFixed(0)}', Colors.green),
                        _metricTile('Udhar Added', 'Rs. ${appStore.todayCreditSales.toStringAsFixed(0)}', Colors.red),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                children: [
                  _bigNavCard(
                    title: 'New Bill',
                    subtitle: 'Create & Print',
                    icon: Icons.receipt_long,
                    color: const Color(0xFF1565C0),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateInvoiceScreen())),
                  ),
                  _bigNavCard(
                    title: 'Customer Ledger',
                    subtitle: 'Udhar Khata',
                    icon: Icons.account_balance_wallet,
                    color: Colors.deepOrange,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerLedgerScreen())),
                  ),
                  _bigNavCard(
                    title: 'History',
                    subtitle: 'Reprint Receipts',
                    icon: Icons.history,
                    color: Colors.teal,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InvoiceHistoryScreen())),
                  ),
                  _bigNavCard(
                    title: 'Products',
                    subtitle: 'Add / Edit Items',
                    icon: Icons.category,
                    color: Colors.indigo,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductCatalogScreen())),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricTile(String title, String value, Color color) {
    return Column(
      children: [
        Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _bigNavCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 4))],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 44, color: Colors.white),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ---------------- 2. CREATE INVOICE SCREEN ----------------
class CreateInvoiceScreen extends StatefulWidget {
  const CreateInvoiceScreen({super.key});

  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> {
  final _nameCtrl = TextEditingController(text: 'Walk-in Customer');
  final _phoneCtrl = TextEditingController();
  final _paidCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');

  List<InvoiceItem> selectedItems = [];
  double previousDue = 0.0;
  String paymentMode = 'Cash';

  void _checkCustomerDue(String _) {
    final key = _phoneCtrl.text.isNotEmpty ? _phoneCtrl.text : _nameCtrl.text;
    if (appStore.customers.containsKey(key)) {
      setState(() => previousDue = appStore.customers[key]!.balance);
    } else {
      setState(() => previousDue = 0.0);
    }
  }

  double get subtotal => selectedItems.fold(0.0, (sum, i) => sum + i.total);
  double get discount => double.tryParse(_discountCtrl.text) ?? 0.0;
  double get grand => (subtotal - discount) > 0 ? (subtotal - discount) : 0.0;
  double get totalPayable => grand + previousDue;
  double get paidAmount => paymentMode == 'Cash' ? totalPayable : (double.tryParse(_paidCtrl.text) ?? 0.0);
  double get remainingDue => (totalPayable - paidAmount) > 0 ? (totalPayable - paidAmount) : 0.0;

  void _openProductPicker() {
    if (appStore.products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catalog is empty! Add products first from the Products screen.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pick POP Product', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 350,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: appStore.products.length,
                itemBuilder: (context, idx) {
                  final p = appStore.products[idx];
                  return InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        selectedItems.add(InvoiceItem(product: p, qty: 1, rate: p.price));
                      });
                    },
                    child: Card(
                      color: Colors.blue.shade50,
                      elevation: 1,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ProductThumb(product: p, size: 52),
                          const SizedBox(height: 4),
                          Text(p.name, textAlign: TextAlign.center, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('Rs. ${p.price.toStringAsFixed(0)}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSavedDialog(Invoice inv) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Invoice Saved!'),
          ],
        ),
        content: Text('${inv.invNumber} saved for ${inv.customerName}.\nPrint thermal receipt?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1565C0), foregroundColor: Colors.white),
            icon: const Icon(Icons.share),
            label: const Text('Print Receipt (Share)'),
            onPressed: () {
              Share.share(inv.toThermalReceiptText(appStore.shopSettings));
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Bill'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(labelText: 'Customer Name', prefixIcon: Icon(Icons.person)),
                          onChanged: _checkCustomerDue,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Quick Walk-in',
                        icon: const Icon(Icons.flash_on, color: Colors.amber, size: 28),
                        onPressed: () {
                          setState(() {
                            _nameCtrl.text = 'Walk-in Customer';
                            _phoneCtrl.clear();
                            previousDue = 0.0;
                          });
                        },
                      ),
                    ],
                  ),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone Number (For Ledger)', prefixIcon: Icon(Icons.phone)),
                    onChanged: _checkCustomerDue,
                  ),
                  if (previousDue > 0)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          const Icon(Icons.warning, color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Text('Previous Due: Rs. ${previousDue.toStringAsFixed(0)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Items Selected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1565C0), foregroundColor: Colors.white),
                onPressed: _openProductPicker,
                icon: const Icon(Icons.add),
                label: const Text('Add Item'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (selectedItems.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: const Text('No items added. Tap "+ Add Item" above.'),
            ),

          // LIST OF ITEMS WITH DELETE BUTTON
          ...selectedItems.asMap().entries.map((entry) {
            int idx = entry.key;
            var item = entry.value;
            return Card(
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    ProductThumb(product: item.product, size: 40),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        initialValue: item.qty.toStringAsFixed(0),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Qty', isDense: true),
                        onChanged: (val) => setState(() => item.qty = double.tryParse(val) ?? 0.0),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        initialValue: item.rate.toStringAsFixed(0),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Rate', isDense: true),
                        onChanged: (val) => setState(() => item.rate = double.tryParse(val) ?? 0.0),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove Item',
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => setState(() => selectedItems.removeAt(idx)),
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 12),
          Card(
            color: Colors.blue.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Subtotal:'), Text('Rs. ${subtotal.toStringAsFixed(0)}')]),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Previous Balance:'), Text('Rs. ${previousDue.toStringAsFixed(0)}')]),
                  const Divider(),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Total Payable:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('Rs. ${totalPayable.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1565C0))),
                  ]),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Cash (Full)')),
                          selected: paymentMode == 'Cash',
                          onSelected: (v) => setState(() => paymentMode = 'Cash'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Udhar / Partial')),
                          selected: paymentMode == 'Credit',
                          onSelected: (v) => setState(() => paymentMode = 'Credit'),
                        ),
                      ),
                    ],
                  ),
                  if (paymentMode == 'Credit') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _paidCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Amount Paid Now (Rs)', border: OutlineInputBorder()),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Remaining Balance (Udhar):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                        Text('Rs. ${remainingDue.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: selectedItems.isEmpty
                ? null
                : () {
                    final inv = Invoice(
                      invNumber: appStore.getNextInvoiceNumber(),
                      date: DateTime.now().toString().substring(0, 16),
                      customerName: _nameCtrl.text.isEmpty ? 'Walk-in Customer' : _nameCtrl.text,
                      customerPhone: _phoneCtrl.text,
                      items: List.from(selectedItems),
                      subtotal: subtotal,
                      discount: discount,
                      grand: grand,
                      paid: paidAmount,
                      previousDue: previousDue,
                      remaining: remainingDue,
                      paymentMethod: paymentMode,
                    );
                    appStore.saveInvoice(inv);
                    _showSavedDialog(inv);
                  },
            child: const Text('Save & Print Invoice', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ---------------- 3. CUSTOMER LEDGER (UDHAR) ----------------
class CustomerLedgerScreen extends StatelessWidget {
  const CustomerLedgerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final list = appStore.customers.values.where((c) => c.balance > 0).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Udhar Khata'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: list.isEmpty
          ? const Center(child: Text('No customer has outstanding balance.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (context, idx) {
                final cust = list[idx];
                return Card(
                  color: Colors.white,
                  child: ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.deepOrange, child: Icon(Icons.person, color: Colors.white)),
                    title: Text(cust.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(cust.phone.isEmpty ? 'No Phone' : cust.phone),
                    trailing: Text('Rs. ${cust.balance.toStringAsFixed(0)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
                    onTap: () {
                      final ctrl = TextEditingController();
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('Collect Udhar: ${cust.name}'),
                          content: TextField(
                            controller: ctrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Amount Received (Rs)'),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                            ElevatedButton(
                              onPressed: () {
                                final amt = double.tryParse(ctrl.text) ?? 0.0;
                                if (amt > 0) {
                                  appStore.recordPayment(cust.key, amt);
                                  Navigator.pop(ctx);
                                }
                              },
                              child: const Text('Record Payment'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

// ---------------- 4. INVOICE HISTORY & REPRINT ----------------
class InvoiceHistoryScreen extends StatelessWidget {
  const InvoiceHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final list = appStore.invoices;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice History'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: list.isEmpty
          ? const Center(child: Text('No invoices recorded yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (context, idx) {
                final inv = list[idx];
                return Card(
                  color: Colors.white,
                  child: ListTile(
                    leading: Icon(
                      inv.synced ? Icons.cloud_done : Icons.cloud_off,
                      color: inv.synced ? Colors.blue : Colors.grey,
                    ),
                    title: Text('${inv.invNumber} — ${inv.customerName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${inv.date} | Total: Rs. ${inv.grand.toStringAsFixed(0)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.share, color: Colors.teal),
                      tooltip: 'Share / Print RawBT',
                      onPressed: () {
                        Share.share(inv.toThermalReceiptText(appStore.shopSettings));
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ---------------- 5. PRODUCT CATALOG (ADD, EDIT, DELETE) ----------------
class ProductCatalogScreen extends StatefulWidget {
  const ProductCatalogScreen({super.key});

  @override
  State<ProductCatalogScreen> createState() => _ProductCatalogScreenState();
}

class _ProductCatalogScreenState extends State<ProductCatalogScreen> {
  final emojis = ['🧱', '⬜', '✨', '📦', '📏', '🕸️', '🌸', '🔨', '⭐', '🛠️', '🪚'];

  void _showProductDialog({Product? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(text: existing != null ? existing.price.toStringAsFixed(0) : '');
    String selectedIcon = existing?.icon ?? '🧱';
    String? selectedImage = existing?.image;
    String selectedCategory = existing?.category ?? 'Tiles';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: Text(existing == null ? 'Add New Product' : 'Edit Product Rate / Name'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Item Name (e.g. 2x2 Plain)')),
                TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rate (Rs)')),
                const SizedBox(height: 12),
                const Text('Picture:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ProductThumb(
                      product: Product(id: 0, name: '', icon: selectedIcon, category: '', price: 0, image: selectedImage),
                      size: 70,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Gallery'),
                            onPressed: () async {
                              try {
                                final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 300, maxHeight: 300, imageQuality: 60);
                                if (f != null) {
                                  final bytes = await f.readAsBytes();
                                  setDState(() => selectedImage = base64Encode(bytes));
                                }
                              } catch (_) {}
                            },
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.photo_camera),
                            label: const Text('Camera'),
                            onPressed: () async {
                              try {
                                final f = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 300, maxHeight: 300, imageQuality: 60);
                                if (f != null) {
                                  final bytes = await f.readAsBytes();
                                  setDState(() => selectedImage = base64Encode(bytes));
                                }
                              } catch (_) {}
                            },
                          ),
                          if (selectedImage != null)
                            TextButton.icon(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              label: const Text('Remove', style: TextStyle(color: Colors.red)),
                              onPressed: () => setDState(() => selectedImage = null),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Or pick Icon:', style: TextStyle(fontWeight: FontWeight.bold)),
                Wrap(
                  spacing: 6,
                  children: emojis
                      .map((e) => ChoiceChip(
                            label: Text(e, style: const TextStyle(fontSize: 18)),
                            selected: selectedIcon == e,
                            onSelected: (s) => setDState(() => selectedIcon = e),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.isNotEmpty) {
                  final price = double.tryParse(priceCtrl.text) ?? 0.0;
                  if (existing == null) {
                    appStore.addProduct(nameCtrl.text, selectedIcon, selectedCategory, price, image: selectedImage);
                  } else {
                    appStore.editProduct(existing.id, nameCtrl.text, selectedIcon, selectedCategory, price, image: selectedImage);
                  }
                  Navigator.pop(ctx);
                  setState(() {});
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Catalog'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Item'),
        onPressed: () => _showProductDialog(),
      ),
      body: appStore.products.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text('No products in catalog yet.\nTap "+ New Item" button below to add your workshop items.', textAlign: TextAlign.center),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: appStore.products.length,
              itemBuilder: (context, idx) {
                final p = appStore.products[idx];
                return Card(
                  color: Colors.white,
                  child: ListTile(
                    leading: ProductThumb(product: p, size: 46),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Rate: Rs. ${p.price.toStringAsFixed(0)}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          tooltip: 'Edit Rate / Name',
                          onPressed: () => _showProductDialog(existing: p),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: 'Delete Item',
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete Product?'),
                                content: Text('Remove "${p.name}" from catalog?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                    onPressed: () {
                                      appStore.deleteProduct(p.id);
                                      Navigator.pop(ctx);
                                      setState(() {});
                                    },
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ---------------- 6. WORKSHOP SETTINGS SCREEN ----------------
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _taglineCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _syncUrlCtrl;

  @override
  void initState() {
    super.initState();
    final s = appStore.shopSettings;
    _nameCtrl = TextEditingController(text: s.name);
    _taglineCtrl = TextEditingController(text: s.tagline);
    _phoneCtrl = TextEditingController(text: s.phone);
    _addressCtrl = TextEditingController(text: s.address);
    _syncUrlCtrl = TextEditingController(text: s.syncUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workshop & Cloud Settings'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Receipt Header Details', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const Divider(height: 20),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Shop Name', prefixIcon: Icon(Icons.store), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _taglineCtrl,
                    decoration: const InputDecoration(labelText: 'Tagline', prefixIcon: Icon(Icons.subtitles), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _addressCtrl,
                    decoration: const InputDecoration(labelText: 'Address', prefixIcon: Icon(Icons.location_on), border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Google Drive & Sheets Sync', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('Google Apps Script Web App URL yahan paste karein. Har invoice bante hi Drive aur Sheet dono me save ho jayegi.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  const Divider(height: 20),
                  TextField(
                    controller: _syncUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Web App URL (https://script.google.com/...)',
                      prefixIcon: Icon(Icons.cloud_upload),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.save),
            label: const Text('Save Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            onPressed: () {
              appStore.updateShopSettings(
                name: _nameCtrl.text.trim().isEmpty ? 'POP WORKSHOP' : _nameCtrl.text.trim(),
                tagline: _taglineCtrl.text.trim(),
                phone: _phoneCtrl.text.trim(),
                address: _addressCtrl.text.trim(),
                syncUrl: _syncUrlCtrl.text.trim(),
              );
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Settings saved successfully!'), backgroundColor: Colors.green),
              );
            },
          ),
        ],
      ),
    );
  }
}
