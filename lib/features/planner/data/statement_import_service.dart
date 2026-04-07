import 'dart:convert';
import 'dart:typed_data';

import 'package:budgie_flutter/features/planner/domain/planner_models.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

class StatementImportParseResult {
  StatementImportParseResult({
    required this.fileName,
    required this.transactions,
  });

  final String fileName;
  final List<StatementImportTransaction> transactions;
}

class StatementImportService {
  StatementImportService._();

  static Future<StatementImportParseResult?> pickAndParseStatement({
    String? debitColumnName,
    String? creditColumnName,
  }) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      return null;
    }

    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    final extension = (file.extension ?? '').toLowerCase();
    final rows = extension == 'xlsx'
        ? _parseXlsxRows(bytes)
        : _parseCsvRows(bytes);

    final transactions = _parseRows(
      rows,
      file.name,
      debitColumnName: debitColumnName,
      creditColumnName: creditColumnName,
    );
    return StatementImportParseResult(
      fileName: file.name,
      transactions: transactions,
    );
  }

  static List<List<String>> _parseCsvRows(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final raw = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(text);

    return raw
        .map(
          (row) => row
              .map((cell) => (cell ?? '').toString().trim())
              .toList(growable: false),
        )
        .toList(growable: false);
  }

  static List<List<String>> _parseXlsxRows(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      return const <List<String>>[];
    }

    final firstTable = excel.tables.values.first;
    if (firstTable.rows.isEmpty) {
      return const <List<String>>[];
    }

    return firstTable.rows
        .map(
          (row) => row
              .map((cell) => (cell?.value ?? '').toString().trim())
              .toList(growable: false),
        )
        .toList(growable: false);
  }

  static List<StatementImportTransaction> _parseRows(
    List<List<String>> rows,
    String fileName,
    {
    String? debitColumnName,
    String? creditColumnName,
  }
  ) {
    if (rows.length < 2) {
      return const <StatementImportTransaction>[];
    }

    final headers = rows.first.map((entry) => entry.toLowerCase()).toList();

    final dateIndex = _findHeader(
      headers,
      const ['date', 'txn date', 'transaction date', 'value date'],
    );
    final amountIndex = _findHeader(
      headers,
      const ['amount', 'txn amount', 'transaction amount'],
    );
    final manualDebit = (debitColumnName ?? '').trim().toLowerCase();
    final manualCredit = (creditColumnName ?? '').trim().toLowerCase();

    final debitIndex = manualDebit.isNotEmpty
        ? _findHeader(headers, [manualDebit])
        : _findHeader(
            headers,
            const ['debit', 'withdrawal', 'dr amount', 'paid out'],
          );
    final creditIndex = manualCredit.isNotEmpty
        ? _findHeader(headers, [manualCredit])
        : _findHeader(
            headers,
            const ['credit', 'deposit', 'cr amount', 'paid in'],
          );
    final descIndex = _findHeader(
      headers,
      const ['description', 'narration', 'remarks', 'particulars', 'note'],
    );
    final refIndex = _findHeader(
      headers,
      const ['reference', 'utr', 'txn id', 'transaction id', 'ref'],
    );
    final typeIndex = _findHeader(
      headers,
      const ['type', 'dr/cr', 'transaction type'],
    );

    final transactions = <StatementImportTransaction>[];

    for (var i = 1; i < rows.length; i += 1) {
      final row = rows[i];
      final date = _parseDate(_cell(row, dateIndex));
      if (date == null) {
        continue;
      }

      final parsed = _extractAmountAndDirection(
        row: row,
        amountIndex: amountIndex,
        debitIndex: debitIndex,
        creditIndex: creditIndex,
        typeIndex: typeIndex,
      );
      if (parsed == null || parsed.$1 <= 0) {
        continue;
      }

      final amount = parsed.$1;
      final direction = parsed.$2;
      final description = _cell(row, descIndex).isEmpty
          ? 'Statement import'
          : _cell(row, descIndex);
      final reference = _cell(row, refIndex);

      final sourceKey = reference.trim().isNotEmpty
          ? reference.trim().toLowerCase()
          : '${DateFormat('yyyy-MM-dd').format(date)}|${amount.toStringAsFixed(2)}|${direction.name}|${description.toLowerCase().trim()}';

      transactions.add(
        StatementImportTransaction(
          sourceKey: sourceKey,
          timestamp: date,
          amount: amount,
          direction: direction,
          description: description,
          reference: reference.trim().isEmpty ? null : reference.trim(),
          sourceFile: fileName,
        ),
      );
    }

    return transactions;
  }

  static (double, SmsImportDirection)? _extractAmountAndDirection({
    required List<String> row,
    required int? amountIndex,
    required int? debitIndex,
    required int? creditIndex,
    required int? typeIndex,
  }) {
    final debit = _parseAmount(_cell(row, debitIndex));
    if (debit != null && debit > 0) {
      return (debit, SmsImportDirection.debit);
    }

    final credit = _parseAmount(_cell(row, creditIndex));
    if (credit != null && credit > 0) {
      return (credit, SmsImportDirection.credit);
    }

    final amount = _parseAmount(_cell(row, amountIndex));
    if (amount == null || amount == 0) {
      return null;
    }

    final type = _cell(row, typeIndex).toLowerCase();
    if (type.contains('credit') || type.contains('cr')) {
      return (amount.abs(), SmsImportDirection.credit);
    }
    if (type.contains('debit') || type.contains('dr')) {
      return (amount.abs(), SmsImportDirection.debit);
    }

    if (amount < 0) {
      return (amount.abs(), SmsImportDirection.debit);
    }
    return (amount.abs(), SmsImportDirection.credit);
  }

  static int? _findHeader(List<String> headers, List<String> aliases) {
    for (final alias in aliases) {
      final index = headers.indexWhere((entry) => entry.contains(alias));
      if (index >= 0) {
        return index;
      }
    }
    return null;
  }

  static String _cell(List<String> row, int? index) {
    if (index == null || index < 0 || index >= row.length) {
      return '';
    }
    return row[index].trim();
  }

  static double? _parseAmount(String raw) {
    if (raw.trim().isEmpty) {
      return null;
    }

    final cleaned = raw
        .replaceAll(',', '')
        .replaceAll('INR', '')
        .replaceAll('Rs.', '')
        .replaceAll('Rs', '')
        .replaceAll('₹', '')
        .trim();

    return double.tryParse(cleaned);
  }

  static DateTime? _parseDate(String raw) {
    if (raw.trim().isEmpty) {
      return null;
    }

    final value = raw.trim();
    final iso = DateTime.tryParse(value);
    if (iso != null) {
      return iso;
    }

    const patterns = [
      'dd/MM/yyyy',
      'd/M/yyyy',
      'dd-MM-yyyy',
      'd-M-yyyy',
      'dd MMM yyyy',
      'dd MMM yy',
      'yyyy/MM/dd',
    ];

    for (final pattern in patterns) {
      try {
        return DateFormat(pattern).parseStrict(value);
      } catch (_) {
        // Try next pattern.
      }
    }

    return null;
  }
}
