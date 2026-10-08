import 'package:flutter/material.dart';
import '/widgets/theme.dart';
import '/widgets/text.dart';
import '/widgets/header.dart';
import '/widgets/card.dart';
import '/services/cow_service.dart';

/// บันทึกวัวที่มีอยู่แล้วในฟาร์ม (ไม่ผูกกับรายจ่าย) — เข้าตรงจากหน้า "บันทึกข้อมูลฟาร์ม"
class ExistingCowRecordPage extends StatefulWidget {
  final String farmId;
  const ExistingCowRecordPage({super.key, required this.farmId});

  @override
  State<ExistingCowRecordPage> createState() => _ExistingCowRecordPageState();
}

class _ExistingCowRecordPageState extends State<ExistingCowRecordPage> {
  final cowService = CowService();
  final countController = TextEditingController();
  List<CowDraft> drafts = [];
  bool isSaving = false;

  @override
  void dispose() {
    countController.dispose();
    super.dispose();
  }

  void _generateDrafts() {
    final count = int.tryParse(countController.text);
    if (count == null || count <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกจำนวนวัวให้ถูกต้อง')),
      );
      return;
    }
    setState(() => drafts = List.generate(count, (_) => CowDraft()));
  }

  Future<void> _save() async {
    setState(() => isSaving = true);
    final error = await cowService.createExistingCows(widget.farmId, drafts);
    if (!mounted) return;
    setState(() => isSaving = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('บันทึกวัว ${drafts.length} ตัวสำเร็จ')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppHeader(farmName: 'บันทึกวัวที่มีอยู่แล้ว', farmId: widget.farmId),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              title: 'จำนวนวัวที่ต้องการบันทึก',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _generateDrafts,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text('สร้างข้อมูล', style: AppTextStyles.button.copyWith(color: Colors.white)),
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
                child: _CowDraftFields(draft: draft, onChanged: () => setState(() {})),
              );
            }),
            if (drafts.isNotEmpty)
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
        ),
      ),
    );
  }
}

class _CowDraftFields extends StatelessWidget {
  final CowDraft draft;
  final VoidCallback onChanged;

  const _CowDraftFields({required this.draft, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _chip('ตัวผู้', draft.gender == 'male', () {
                draft.gender = 'male';
                onChanged();
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _chip('ตัวเมีย', draft.gender == 'female', () {
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
                child: _chip('ปกติ', draft.pregnancyStatus == 'ปกติ', () {
                  draft.pregnancyStatus = 'ปกติ';
                  onChanged();
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _chip('ท้อง', draft.pregnancyStatus == 'ท้อง', () {
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

  Widget _chip(String label, bool selected, VoidCallback onTap) {
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