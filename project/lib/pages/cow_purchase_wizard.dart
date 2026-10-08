import 'package:flutter/material.dart';
import '/widgets/theme.dart';
import '/widgets/text.dart';
import '/widgets/header.dart';
import '/widgets/card.dart';
import '/services/cow_service.dart';

/// wizard 2 ขั้นตอนสำหรับ "ซื้อวัว" — เข้าได้ทั้งจากหน้ารายจ่ายและหน้าบันทึกวัว
/// แต่ทั้งสองทางมาจบที่ flow เดียวกัน: กรอกจำนวน+ราคารวมก่อน แล้วค่อยกรอกรายละเอียดทีละตัว
/// จะบันทึกลง database ก็ต่อเมื่อกรอกครบทั้ง 2 ขั้นตอนเท่านั้น (กด "บันทึก" ครั้งเดียวจบ)
class CowPurchaseWizard extends StatefulWidget {
  final String farmId;
  const CowPurchaseWizard({super.key, required this.farmId});

  @override
  State<CowPurchaseWizard> createState() => _CowPurchaseWizardState();
}

class _CowPurchaseWizardState extends State<CowPurchaseWizard> {
  final cowService = CowService();

  int step = 0; // 0 = จำนวน+ราคารวม, 1 = รายละเอียดแต่ละตัว
  DateTime selectedDate = DateTime.now();
  final countController = TextEditingController();
  final priceController = TextEditingController();
  List<CowDraft> drafts = [];
  bool isSaving = false;

  @override
  void dispose() {
    countController.dispose();
    priceController.dispose();
    super.dispose();
  }

  Future<bool> _confirmExit() async {
    if (countController.text.isEmpty && priceController.text.isEmpty && drafts.isEmpty) {
      return true; // ยังไม่ได้กรอกอะไรเลย ออกได้เลยไม่ต้องเตือน
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยกเลิกการบันทึก?'),
        content: const Text('ข้อมูลที่กรอกไว้จะหายไปทั้งหมด ถ้าออกตอนนี้'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('กรอกต่อ')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ออกเลย', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  void _goToDetailStep() {
    final count = int.tryParse(countController.text);
    final price = double.tryParse(priceController.text);

    if (count == null || count <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกจำนวนวัวให้ถูกต้อง')),
      );
      return;
    }
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกจำนวนเงินให้ถูกต้อง')),
      );
      return;
    }

    setState(() {
      drafts = List.generate(count, (_) => CowDraft());
      step = 1;
    });
  }

  Future<void> _save() async {
    setState(() => isSaving = true);

    final error = await cowService.createCowPurchase(
      farmId: widget.farmId,
      recordDate: selectedDate.toIso8601String().split('T').first,
      totalPrice: double.parse(priceController.text),
      cows: drafts,
    );

    if (!mounted) return;
    setState(() => isSaving = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('บันทึกซื้อวัว ${drafts.length} ตัวสำเร็จ')),
    );
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmExit() && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppHeader(farmName: 'บันทึกซื้อวัว', farmId: widget.farmId),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StepIndicator(step: step),
              const SizedBox(height: 16),
              if (step == 0) _buildAmountStep() else _buildDetailStep(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAmountStep() {
    return SectionCard(
      title: 'ข้อมูลการซื้อวัว',
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
              child: Text('${selectedDate.day}/${selectedDate.month}/${selectedDate.year}', style: AppTextStyles.body),
            ),
          ),
          const SizedBox(height: 14),
          Text('จำนวนวัวที่ซื้อ (ตัว)', style: AppTextStyles.bodySecondary),
          const SizedBox(height: 4),
          TextField(
            controller: countController,
            keyboardType: TextInputType.number,
            style: AppTextStyles.body,
            decoration: InputDecoration(
              hintText: '0',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 14),
          Text('จำนวนเงินทั้งหมด (บาท)', style: AppTextStyles.bodySecondary),
          const SizedBox(height: 4),
          TextField(
            controller: priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTextStyles.body,
            decoration: InputDecoration(
              hintText: '0',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _goToDetailStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('ถัดไป', style: AppTextStyles.button.copyWith(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailStep() {
    final pricePerCow = double.parse(priceController.text) / drafts.length;

    return Column(
      children: [
        SectionCard(
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ราคาเฉลี่ยตัวละ ${pricePerCow.toStringAsFixed(0)} บาท (จากทั้งหมด ${drafts.length} ตัว)',
                  style: AppTextStyles.bodySecondary,
                ),
              ),
            ],
          ),
        ),
        ...drafts.asMap().entries.map((entry) {
          final index = entry.key;
          final draft = entry.value;
          return SectionCard(
            title: 'วัวตัวที่ ${index + 1}',
            child: _CowDraftForm(
              draft: draft,
              onChanged: () => setState(() {}),
            ),
          );
        }),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              isSaving ? 'กำลังบันทึก...' : 'บันทึก',
              style: AppTextStyles.button.copyWith(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final int step;
  const _StepIndicator({required this.step});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _dot(0, 'จำนวน+ราคา'),
        Expanded(child: Container(height: 1, color: AppColors.border)),
        _dot(1, 'รายละเอียด'),
      ],
    );
  }

  Widget _dot(int index, String label) {
    final isActive = step == index;
    final isDone = step > index;
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive || isDone ? AppColors.primary : AppColors.surfaceMuted,
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : Text('${index + 1}', style: TextStyle(color: isActive ? Colors.white : AppColors.textMuted, fontSize: 13)),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }
}

class _CowDraftForm extends StatelessWidget {
  final CowDraft draft;
  final VoidCallback onChanged;

  const _CowDraftForm({required this.draft, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _choiceChip('ตัวผู้', draft.gender == 'male', () {
                draft.gender = 'male';
                onChanged();
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _choiceChip('ตัวเมีย', draft.gender == 'female', () {
                draft.gender = 'female';
                onChanged();
              }),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (draft.gender == 'female')
          Row(
            children: [
              Expanded(
                child: _choiceChip('ปกติ', draft.pregnancyStatus == 'ปกติ', () {
                  draft.pregnancyStatus = 'ปกติ';
                  onChanged();
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _choiceChip('ท้อง', draft.pregnancyStatus == 'ท้อง', () {
                  draft.pregnancyStatus = 'ท้อง';
                  onChanged();
                }),
              ),
            ],
          ),
        const SizedBox(height: 8),
        TextField(
          style: AppTextStyles.body,
          decoration: InputDecoration(
            hintText: 'ชื่อเล่น (ถ้ามี)',
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (v) => draft.nickname = v,
        ),
      ],
    );
  }

  Widget _choiceChip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppColors.primary : Colors.transparent),
        ),
        child: Text(
          label,
          style: AppTextStyles.body.copyWith(
            color: selected ? AppColors.primary : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}