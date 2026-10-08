import 'package:flutter/material.dart';
import '/widgets/theme.dart';
import '/widgets/text.dart';
import '/widgets/header.dart';
import '/widgets/card.dart';
import '/services/finance_service.dart';
import '/services/cow_service.dart';
import 'cow_purchase_wizard.dart';


enum _EntryType { income, expense }

enum _ExpenseCategory { cow, medicine, feed }

/// หน้ารวมรายรับ-รายจ่าย
/// รายรับ: เลือกวัวขายได้ทั้งแบบเป็นล็อต (ตามวันที่ซื้อ) หรือทีละตัวจากวัวที่มีอยู่แล้ว
///         เตือนทันทีถ้าเลือกวัวท้อง และจำการยืนยันไว้ไม่ถามซ้ำในเซสชันเดียวกัน
/// รายจ่าย: ซื้อวัวพาไป wizard แยก, ซื้อยา/ซื้ออาหารกรอกได้หลายรายการในครั้งเดียว (ปุ่ม +)
class ExpenseIncomePage extends StatefulWidget {
  final String farmId;
  const ExpenseIncomePage({super.key, required this.farmId});

  @override
  State<ExpenseIncomePage> createState() => _ExpenseIncomePageState();
}

class _ExpenseIncomePageState extends State<ExpenseIncomePage> {
  final financeService = FinanceService();
  final cowService = CowService();

  _EntryType entryType = _EntryType.income;
  _ExpenseCategory expenseCategory = _ExpenseCategory.medicine;
  DateTime selectedDate = DateTime.now();

  // ---------- รายรับ (ขายวัว) ----------
  List<Map<String, dynamic>> availableCows = [];
  bool isLoadingCows = true;
  final Set<String> selectedCowIds = {};
  final Set<String> confirmedPregnantIds = {}; // ยืนยันขายวัวท้องแล้ว ไม่ต้องเตือนซ้ำ
  String? selectedLotDate; // ล็อตที่กำลังดูอยู่ใน dropdown ล็อต
  String? selectedIndividualCowId; // ตัวที่เลือกใน dropdown วัวที่มีอยู่แล้ว
  final saleAmountController = TextEditingController();
  bool isSaving = false;

  // ---------- รายจ่าย (ซื้อยา/ซื้ออาหาร หลายรายการ) ----------
  final List<_ExpenseLineItem> expenseLines = [_ExpenseLineItem()];

  @override
  void initState() {
    super.initState();
    _loadAvailableCows();
  }

  @override
  void dispose() {
    saleAmountController.dispose();
    for (final line in expenseLines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAvailableCows() async {
    setState(() => isLoadingCows = true);
    final cows = await cowService.getCows(widget.farmId, availableForSaleOnly: true);
    if (!mounted) return;
    setState(() {
      availableCows = cows;
      isLoadingCows = false;
    });
  }

  // จัดกลุ่มวัวที่ "ซื้อมาใหม่" เป็นล็อตตามวันที่ซื้อ เรียงใหม่สุดก่อน
  Map<String, List<Map<String, dynamic>>> get _lots {
    final purchased = availableCows.where((c) => c['origin_type'] == 'ซื้อมาใหม่').toList();
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final cow in purchased) {
      final date = '${cow['purchase_date'] ?? 'ไม่ระบุวันที่'}';
      grouped.putIfAbsent(date, () => []).add(cow);
    }
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return {for (final k in sortedKeys) k: grouped[k]!};
  }

  // วัวที่ "มีอยู่แล้ว" ไม่มีล็อต เลือกทีละตัว
  List<Map<String, dynamic>> get _individualCows =>
      availableCows.where((c) => c['origin_type'] != 'ซื้อมาใหม่').toList();

  String _cowLabel(Map<String, dynamic> cow) {
    final isPurchased = cow['origin_type'] == 'ซื้อมาใหม่' && cow['purchase_date'] != null;
    final lot = isPurchased ? 'ล็อตที่ ${cow['purchase_date']}' : '';
    final hasNickname = cow['nickname'] != null && cow['nickname'] != '';
    final nickname = hasNickname ? cow['nickname'] : '';
    final gender = cow['gender'] == 'male' ? 'ตัวผู้' : 'ตัวเมีย';
    final pregnancy = cow['pregnancy_status'] == 'ท้อง' ? ' • ท้อง' : '';
    final parts = [lot, nickname, gender].where((s) => s.isNotEmpty);
    return parts.join(' • ') + pregnancy;
  }

  Future<bool> _confirmPregnantSale(Map<String, dynamic> cow) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('วัวตัวนี้กำลังท้องอยู่'),
        content: Text('${_cowLabel(cow)}\n\nต้องการขายวัวที่กำลังท้องอยู่หรือไม่'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ไม่ขาย'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ขายเลย', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// เพิ่ม/เอาวัวออกจากรายการที่เลือก — ถ้าเป็นวัวท้องและยังไม่เคยยืนยัน จะเด้งเตือนก่อน
  Future<void> _toggleCow(Map<String, dynamic> cow) async {
    final id = '${cow['cow_id']}';

    if (selectedCowIds.contains(id)) {
      setState(() => selectedCowIds.remove(id));
      return;
    }

    final isPregnant = cow['pregnancy_status'] == 'ท้อง';
    if (isPregnant && !confirmedPregnantIds.contains(id)) {
      final confirmed = await _confirmPregnantSale(cow);
      if (!confirmed) return; // ไม่ขาย ไม่ต้องเพิ่มเข้ารายการ
      confirmedPregnantIds.add(id);
    }

    if (!mounted) return;
    setState(() => selectedCowIds.add(id));
  }

  Future<void> _saveSale() async {
    if (selectedCowIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาเลือกวัวที่ต้องการขาย')));
      return;
    }
    final amount = double.tryParse(saleAmountController.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณากรอกจำนวนเงิน')));
      return;
    }

    setState(() => isSaving = true);
    final error = await cowService.createCowSale(
      farmId: widget.farmId,
      recordDate: selectedDate.toIso8601String().split('T').first,
      totalPrice: amount,
      cowIds: selectedCowIds.toList(),
    );

    if (!mounted) return;
    setState(() => isSaving = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกรายรับสำเร็จ')));
    setState(() {
      selectedCowIds.clear();
      saleAmountController.clear();
    });
    _loadAvailableCows();
  }

  Future<void> _saveExpenseLines() async {
    for (final line in expenseLines) {
      if (line.noteController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณากรอกรายละเอียดให้ครบทุกรายการ')));
        return;
      }
      if (double.tryParse(line.amountController.text) == null || double.parse(line.amountController.text) <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณากรอกจำนวนเงินให้ถูกต้องทุกรายการ')));
        return;
      }
    }

    setState(() => isSaving = true);
    final error = await financeService.createFinanceEntries(
      farmId: widget.farmId,
      recordDate: selectedDate.toIso8601String().split('T').first,
      category: expenseCategory == _ExpenseCategory.medicine ? 'medicine' : 'feed',
      entries: expenseLines
          .map((l) => {'note': l.noteController.text.trim(), 'amount': double.parse(l.amountController.text)})
          .toList(),
    );

    if (!mounted) return;
    setState(() => isSaving = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกสำเร็จ')));
    setState(() {
      for (final line in expenseLines) {
        line.dispose();
      }
      expenseLines
        ..clear()
        ..add(_ExpenseLineItem());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppHeader(farmName: 'รายรับ-รายจ่าย', farmId: widget.farmId),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _dateAndTypeRow(),
            const SizedBox(height: 16),
            entryType == _EntryType.income ? _buildIncomeForm() : _buildExpenseForm(),
          ],
        ),
      ),
    );
  }

  Widget _dateAndTypeRow() {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('วันที่', style: AppTextStyles.bodySecondary),
          const SizedBox(height: 4),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => selectedDate = picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
              child: Text('${selectedDate.day}/${selectedDate.month}/${selectedDate.year}', style: AppTextStyles.body),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _typeToggle('รายรับ', entryType == _EntryType.income, () => setState(() => entryType = _EntryType.income))),
              const SizedBox(width: 8),
              Expanded(child: _typeToggle('รายจ่าย', entryType == _EntryType.expense, () => setState(() => entryType = _EntryType.expense))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _typeToggle(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: selected ? AppColors.primary : AppColors.surfaceMuted, borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: AppTextStyles.body.copyWith(color: selected ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ================= รายรับ =================

  Widget _buildIncomeForm() {
    if (isLoadingCows) {
      return const SectionCard(child: Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())));
    }

    if (availableCows.isEmpty) {
      return SectionCard(child: Text('ไม่มีวัวที่สามารถขายได้ในตอนนี้', style: AppTextStyles.bodySecondary));
    }

    return Column(
      children: [
        if (_lots.isNotEmpty) _buildLotPicker(),
        if (_individualCows.isNotEmpty) _buildIndividualPicker(),
        if (selectedCowIds.isNotEmpty) _buildSelectedSummary(),
        SectionCard(
          title: 'จำนวนเงินทั้งหมดที่ขายได้',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: saleAmountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  hintText: '0 บาท',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: isSaving ? null : _saveSale,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text(isSaving ? 'กำลังบันทึก...' : 'บันทึก', style: AppTextStyles.button.copyWith(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLotPicker() {
    final lots = _lots;
    final lotCows = selectedLotDate != null ? lots[selectedLotDate] ?? [] : <Map<String, dynamic>>[];

    return SectionCard(
      title: 'เลือกจากล็อตที่ซื้อมา',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: selectedLotDate,
            decoration: InputDecoration(
              hintText: 'เลือกล็อต',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            items: lots.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text('ล็อตวันที่ ${e.key} (${e.value.length} ตัว)')))
                .toList(),
            onChanged: (v) => setState(() => selectedLotDate = v),
          ),
          if (lotCows.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...lotCows.map((cow) {
              final id = '${cow['cow_id']}';
              final selected = selectedCowIds.contains(id);
              return CheckboxListTile(
                value: selected,
                onChanged: (_) => _toggleCow(cow),
                title: Text(_cowLabel(cow), style: AppTextStyles.body),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildIndividualPicker() {
    final notSelected = _individualCows.where((c) => !selectedCowIds.contains('${c['cow_id']}')).toList();

    return SectionCard(
      title: 'เลือกจากวัวที่มีอยู่แล้ว',
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: selectedIndividualCowId,
              decoration: InputDecoration(
                hintText: 'เลือกวัว',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: notSelected
                  .map((c) => DropdownMenuItem(value: '${c['cow_id']}', child: Text(_cowLabel(c), overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setState(() => selectedIndividualCowId = v),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: selectedIndividualCowId == null
                ? null
                : () async {
                    final cow = availableCows.firstWhere((c) => '${c['cow_id']}' == selectedIndividualCowId);
                    await _toggleCow(cow);
                    setState(() => selectedIndividualCowId = null);
                  },
            icon: const Icon(Icons.add),
            style: IconButton.styleFrom(backgroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedSummary() {
    final selectedCows = availableCows.where((c) => selectedCowIds.contains('${c['cow_id']}')).toList();
    return SectionCard(
      title: 'รายการที่เลือก (${selectedCows.length} ตัว)',
      child: Column(
        children: selectedCows.map((cow) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(_cowLabel(cow), style: AppTextStyles.body)),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                  onPressed: () => setState(() => selectedCowIds.remove('${cow['cow_id']}')),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ================= รายจ่าย =================

  Widget _buildExpenseForm() {
    return SectionCard(
      title: 'รายจ่าย',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _categoryChip('ซื้อวัว', _ExpenseCategory.cow)),
              const SizedBox(width: 8),
              Expanded(child: _categoryChip('ซื้อยา', _ExpenseCategory.medicine)),
              const SizedBox(width: 8),
              Expanded(child: _categoryChip('ซื้ออาหาร', _ExpenseCategory.feed)),
            ],
          ),
          const SizedBox(height: 14),
          if (expenseCategory == _ExpenseCategory.cow) _buildCowExpenseLink() else _buildExpenseLines(),
        ],
      ),
    );
  }

  Widget _buildCowExpenseLink() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('การซื้อวัวต้องบันทึกข้อมูลวัวแต่ละตัวไปพร้อมกัน', style: AppTextStyles.bodySecondary),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => CowPurchaseWizard(farmId: widget.farmId)))
                  .then((_) => _loadAvailableCows());
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text('ไปบันทึกซื้อวัว', style: AppTextStyles.button.copyWith(color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _buildExpenseLines() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...expenseLines.asMap().entries.map((entry) {
          final index = entry.key;
          final line = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: line.noteController,
                    style: AppTextStyles.body,
                    decoration: InputDecoration(
                      labelText: 'รายละเอียด',
                      hintText: expenseCategory == _ExpenseCategory.medicine ? 'เช่น ยาถ่ายพยาธิ' : 'เช่น หญ้าแห้ง',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: line.amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: AppTextStyles.body,
                    decoration: InputDecoration(
                      labelText: 'บาท',
                      hintText: '0',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                if (expenseLines.length > 1)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                    onPressed: () => setState(() {
                      expenseLines[index].dispose();
                      expenseLines.removeAt(index);
                    }),
                  ),
              ],
            ),
          );
        }),
        OutlinedButton.icon(
          onPressed: () => setState(() => expenseLines.add(_ExpenseLineItem())),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('เพิ่มรายการ'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: isSaving ? null : _saveExpenseLines,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text(isSaving ? 'กำลังบันทึก...' : 'บันทึก', style: AppTextStyles.button.copyWith(color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _categoryChip(String label, _ExpenseCategory category) {
    final selected = expenseCategory == category;
    return InkWell(
      onTap: () => setState(() => expenseCategory = category),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppColors.primary : Colors.transparent),
        ),
        child: Text(label, style: AppTextStyles.body.copyWith(color: selected ? AppColors.primary : AppColors.textSecondary, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }
}

class _ExpenseLineItem {
  final noteController = TextEditingController();
  final amountController = TextEditingController();

  void dispose() {
    noteController.dispose();
    amountController.dispose();
  }
}