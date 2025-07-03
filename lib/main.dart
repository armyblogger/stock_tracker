import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => StockProvider(),
      child: const MyApp(),
    ),
  );
}

class Stock {
  String ticker;
  double buyPrice;
  int shares;
  double? currentPrice;
  double? high52w;
  double? low52w;
  double? high24h;
  double? low24h;
  double? high1w;
  double? low1w;
  double? prevClose;

  Stock({
    required this.ticker,
    required this.buyPrice,
    required this.shares,
    this.currentPrice,
    this.high52w,
    this.low52w,
    this.high24h,
    this.low24h,
    this.high1w,
    this.low1w,
    this.prevClose,
  });

  Map<String, dynamic> toJson() => {
        'ticker': ticker,
        'buyPrice': buyPrice,
        'shares': shares,
        'prevClose': prevClose,
      };

  factory Stock.fromJson(Map<String, dynamic> json) => Stock(
        ticker: json['ticker'],
        buyPrice: json['buyPrice'],
        shares: json['shares'],
        prevClose: json['prevClose']?.toDouble(),
      );
}

class StockProvider extends ChangeNotifier {
  List<Stock> stocks = [];
  bool loading = false;

  StockProvider() {
    loadStocks();
  }

  Future<void> loadStocks() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('stocks');
    if (data != null) {
      stocks = (json.decode(data) as List)
          .map((e) => Stock.fromJson(e))
          .toList();
      await refreshAll();
    }
    notifyListeners();
  }

  Future<void> saveStocks() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('stocks', json.encode(stocks.map((e) => e.toJson()).toList()));
  }

  Future<void> addStock(Stock stock) async {
    stocks.add(stock);
    await saveStocks();
    await fetchStockData(stock);
    notifyListeners();
  }

  Future<void> fetchStockData(Stock stock) async {
    loading = true;
    notifyListeners();
    final data = await StockApiService.fetchStockData(stock.ticker);
    if (data != null) {
      stock.currentPrice = data['c']?.toDouble();
      stock.high52w = data['52wHigh']?.toDouble();
      stock.low52w = data['52wLow']?.toDouble();
      stock.high24h = data['24hHigh']?.toDouble();
      stock.low24h = data['24hLow']?.toDouble();
      stock.high1w = data['1wHigh']?.toDouble();
      stock.low1w = data['1wLow']?.toDouble();
      stock.prevClose = data['pc']?.toDouble();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> refreshAll() async {
    for (var stock in stocks) {
      await fetchStockData(stock);
    }
  }

  double get portfolioValue => stocks.fold(0, (sum, s) => sum + ((s.currentPrice ?? 0) * s.shares));
  double get portfolioCost => stocks.fold(0, (sum, s) => sum + (s.buyPrice * s.shares));
  double get portfolioGain => portfolioValue - portfolioCost;
  double get portfolioGainPercent => portfolioCost == 0 ? 0 : (portfolioGain / portfolioCost) * 100;
  double get portfolioDayGain => stocks.fold(0, (sum, s) => sum + ((s.currentPrice ?? 0 - (s.prevClose ?? 0)) * s.shares));
  double get portfolioDayGainPercent {
    final prev = stocks.fold(0.0, (sum, s) => sum + ((s.prevClose ?? 0) * s.shares));
    return prev == 0 ? 0 : (portfolioDayGain / prev) * 100;
  }

  // Per-stock helpers
  double stockDayGain(Stock s) => (s.currentPrice ?? 0) - (s.prevClose ?? 0);
  double stockDayGainPercent(Stock s) => (s.prevClose ?? 0) == 0 ? 0 : (stockDayGain(s) / (s.prevClose ?? 1)) * 100;
  double stockTotalGain(Stock s) => (s.currentPrice ?? 0 - s.buyPrice) * s.shares;
  double stockTotalGainPercent(Stock s) => s.buyPrice == 0 ? 0 : (((s.currentPrice ?? 0) - s.buyPrice) / s.buyPrice) * 100;
  double stockCostBasisTotal(Stock s) => s.buyPrice * s.shares;
  double stockAverageCostBasis(Stock s) => s.buyPrice;

  Future<void> editStock(int index, Stock updatedStock) async {
    stocks[index] = updatedStock;
    await saveStocks();
    await fetchStockData(updatedStock);
    notifyListeners();
  }

  Future<void> deleteStock(int index) async {
    stocks.removeAt(index);
    await saveStocks();
    notifyListeners();
  }
}

class StockApiService {
  // Your Finnhub API key
  static const String _apiKey = 'd1iohp9r01qhbuvra7mgd1iohp9r01qhbuvra7n0';
  static const String _baseUrl = 'https://finnhub.io/api/v1';

  static Future<Map<String, dynamic>?> fetchStockData(String ticker) async {
    try {
      final quoteUrl = '$_baseUrl/quote?symbol=$ticker&token=$_apiKey';
      final res = await http.get(Uri.parse(quoteUrl));
      if (res.statusCode != 200) return null;
      final quote = json.decode(res.body);

      // For 52w high/low, Finnhub provides a separate endpoint
      final metricUrl = '$_baseUrl/stock/metric?symbol=$ticker&metric=all&token=$_apiKey';
      final metricRes = await http.get(Uri.parse(metricUrl));
      Map<String, dynamic> metrics = {};
      if (metricRes.statusCode == 200) {
        metrics = json.decode(metricRes.body)['metric'] ?? {};
      }

      // For 24h and 1w high/low, Finnhub does not provide directly, so we skip or set as null
      return {
        'c': quote['c'], // current price
        'pc': quote['pc'], // previous close
        '52wHigh': metrics['52WeekHigh'],
        '52wLow': metrics['52WeekLow'],
        '24hHigh': null,
        '24hLow': null,
        '1wHigh': null,
        '1wLow': null,
      };
    } catch (e) {
      return null;
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stock Tracker',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<StockProvider>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => provider.refreshAll(),
          ),
        ],
      ),
      body: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : provider.stocks.isEmpty
              ? const Center(child: Text('No stocks added.'))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Card(
                        color: Colors.grey[100],
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Portfolio Value: '
                                  '${provider.portfolioValue.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 20)),
                              Row(
                                children: [
                                  Text(
                                    'Day: '
                                    '${provider.portfolioDayGain >= 0 ? '+' : ''}'
                                    '${provider.portfolioDayGain.toStringAsFixed(2)} '
                                    '(${provider.portfolioDayGainPercent >= 0 ? '+' : ''}${provider.portfolioDayGainPercent.toStringAsFixed(2)}%)',
                                    style: TextStyle(
                                      color: provider.portfolioDayGain >= 0 ? Colors.green : Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    'Total: '
                                    '${provider.portfolioGain >= 0 ? '+' : ''}'
                                    '${provider.portfolioGain.toStringAsFixed(2)} '
                                    '(${provider.portfolioGainPercent >= 0 ? '+' : ''}${provider.portfolioGainPercent.toStringAsFixed(2)}%)',
                                    style: TextStyle(
                                      color: provider.portfolioGain >= 0 ? Colors.green : Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: provider.stocks.length,
                        itemBuilder: (context, i) {
                          final stock = provider.stocks[i];
                          final dayGain = provider.stockDayGain(stock) * stock.shares;
                          final dayGainPercent = provider.stockDayGainPercent(stock);
                          final totalGain = provider.stockTotalGain(stock);
                          final totalGainPercent = provider.stockTotalGainPercent(stock);
                          final costBasisTotal = provider.stockCostBasisTotal(stock);
                          return Card(
                            child: ListTile(
                              title: Text('${stock.ticker} (${stock.shares} shares)'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Latest: ${stock.currentPrice?.toStringAsFixed(2) ?? 'N/A'}'),
                                  Text('Buy Price: ${stock.buyPrice.toStringAsFixed(2)}'),
                                  Text('Cost Basis: $costBasisTotal'),
                                  Row(
                                    children: [
                                      Text(
                                        'Day: '
                                        '${dayGain >= 0 ? '+' : ''}'
                                        '${dayGain.toStringAsFixed(2)} '
                                        '(${dayGainPercent >= 0 ? '+' : ''}${dayGainPercent.toStringAsFixed(2)}%)',
                                        style: TextStyle(
                                          color: dayGain >= 0 ? Colors.green : Colors.red,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Total: '
                                        '${totalGain >= 0 ? '+' : ''}'
                                        '${totalGain.toStringAsFixed(2)} '
                                        '(${totalGainPercent >= 0 ? '+' : ''}${totalGainPercent.toStringAsFixed(2)}%)',
                                        style: TextStyle(
                                          color: totalGain >= 0 ? Colors.green : Colors.red,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text('Avg Cost: ${stock.buyPrice.toStringAsFixed(2)}'),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.info_outline),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => StockDetailScreen(stock: stock),
                                        ),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => EditStockScreen(stock: stock, index: i),
                                        ),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text('Delete Stock'),
                                          content: const Text('Are you sure you want to delete this stock?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, false),
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, true),
                                              child: const Text('Delete'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await provider.deleteStock(i);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddStockScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class AddStockScreen extends StatefulWidget {
  const AddStockScreen({super.key});
  @override
  State<AddStockScreen> createState() => _AddStockScreenState();
}

class _AddStockScreenState extends State<AddStockScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tickerController = TextEditingController();
  final _buyPriceController = TextEditingController();
  final _sharesController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<StockProvider>(context, listen: false);
    return Scaffold(
      appBar: AppBar(title: const Text('Add Stock')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _tickerController,
                decoration: const InputDecoration(labelText: 'Ticker (e.g. AAPL)'),
                validator: (v) => v == null || v.isEmpty ? 'Enter ticker' : null,
              ),
              TextFormField(
                controller: _buyPriceController,
                decoration: const InputDecoration(labelText: 'Buy Price'),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || v.isEmpty ? 'Enter buy price' : null,
              ),
              TextFormField(
                controller: _sharesController,
                decoration: const InputDecoration(labelText: 'Shares Owned'),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || v.isEmpty ? 'Enter shares' : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    final stock = Stock(
                      ticker: _tickerController.text.toUpperCase(),
                      buyPrice: double.parse(_buyPriceController.text),
                      shares: int.parse(_sharesController.text),
                    );
                    await provider.addStock(stock);
                    if (mounted) Navigator.pop(context);
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StockDetailScreen extends StatelessWidget {
  final Stock stock;
  const StockDetailScreen({super.key, required this.stock});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${stock.ticker} Details')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ticker: ${stock.ticker}', style: const TextStyle(fontSize: 20)),
            Text('Buy Price: \$${stock.buyPrice.toStringAsFixed(2)}'),
            Text('Shares: ${stock.shares}'),
            const SizedBox(height: 10),
            if (stock.currentPrice != null)
              Text('Current Price: \$${stock.currentPrice!.toStringAsFixed(2)}'),
            if (stock.high52w != null && stock.low52w != null)
              Text('52w High: \$${stock.high52w!.toStringAsFixed(2)}'),
            if (stock.high52w != null && stock.low52w != null)
              Text('52w Low: \$${stock.low52w!.toStringAsFixed(2)}'),
            if (stock.high24h != null && stock.low24h != null)
              Text('24h High: \$${stock.high24h!.toStringAsFixed(2)}'),
            if (stock.high24h != null && stock.low24h != null)
              Text('24h Low: \$${stock.low24h!.toStringAsFixed(2)}'),
            if (stock.high1w != null && stock.low1w != null)
              Text('1w High: \$${stock.high1w!.toStringAsFixed(2)}'),
            if (stock.high1w != null && stock.low1w != null)
              Text('1w Low: \$${stock.low1w!.toStringAsFixed(2)}'),
          ],
        ),
      ),
    );
  }
}

class EditStockScreen extends StatefulWidget {
  final Stock stock;
  final int index;
  const EditStockScreen({super.key, required this.stock, required this.index});
  @override
  State<EditStockScreen> createState() => _EditStockScreenState();
}

class _EditStockScreenState extends State<EditStockScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tickerController = TextEditingController();
  final _buyPriceController = TextEditingController();
  final _sharesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tickerController.text = widget.stock.ticker;
    _buyPriceController.text = widget.stock.buyPrice.toString();
    _sharesController.text = widget.stock.shares.toString();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<StockProvider>(context, listen: false);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Stock')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _tickerController,
                decoration: const InputDecoration(labelText: 'Ticker (e.g. AAPL)'),
                validator: (v) => v == null || v.isEmpty ? 'Enter ticker' : null,
              ),
              TextFormField(
                controller: _buyPriceController,
                decoration: const InputDecoration(labelText: 'Buy Price'),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || v.isEmpty ? 'Enter buy price' : null,
              ),
              TextFormField(
                controller: _sharesController,
                decoration: const InputDecoration(labelText: 'Shares Owned'),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || v.isEmpty ? 'Enter shares' : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    final updatedStock = Stock(
                      ticker: _tickerController.text.toUpperCase(),
                      buyPrice: double.parse(_buyPriceController.text),
                      shares: int.parse(_sharesController.text),
                    );
                    await provider.editStock(widget.index, updatedStock);
                    if (mounted) Navigator.pop(context);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
