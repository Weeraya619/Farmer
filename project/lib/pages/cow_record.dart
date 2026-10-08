import 'package:flutter/material.dart';
import '/widgets/theme.dart';
import '/widgets/text.dart';
import '/widgets/header.dart';
import '/widgets/card.dart';
import '/services/cow_service.dart';
import 'cow_purchase_wizard.dart';

/// จุดเข้า "บันทึกข้อมูลวัว" — เลือกโหมดก่อนว่าเป็นวัวที่มีอยู่แล้ว (ไม่ผูกรายจ่าย)
/// หรือวัวที่ซื้อมาใหม่ (ผูกกับรายจ่ายเสมอ → ไปต่อที่ wizard)
class CowRecordPage extends StatefulWidget {
  final String farmId;
  const CowRecordPage({super.key, required this.farmId});

  @override
  State<CowRecordPage> createState() => _CowRecordPageState();
}

class _CowRecordPageState extends State<CowRecordPage> {
  final cowService = CowService();

  bool showExistingForm = false;
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

  Future<void> _saveExisting() async {
    setState(() => isSaving = true);
    final error = await cowService.createExistingCows(widget.farmId, drafts);
    if (!mounted) return;
    setState(() => isSaving = false);

    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
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
      appBar: const AppHeader(farmName: 'บันทึกข้อมูลวัว'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: _ModeCard(
                    label: 'วัวที่มีอยู่แล้ว',
                    sublabel: 'บันทึกย้อนหลัง ไม่ผูกรายจ่าย',
                    icon: Icons.pets_outlined,
                    isSelected: showExistingForm,
                    onTap: () => setState(() {
                      showExistingForm = true;
                      drafts = [];
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ModeCard(
                    label: 'วัวที่ซื้อมาใหม่',
                    sublabel: 'ผูกกับรายจ่ายอัตโนมัติ',
                    icon: Icons.shopping_cart_outlined,
                    isSelected: false,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              CowPurchaseWizard(farmId: widget.farmId),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (showExistingForm) ...[
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
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'สร้างข้อมูล',
                          style: AppTextStyles.button.copyWith(
                            color: Colors.white,
                          ),
                        ),
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
                  child: _CowDraftFields(
                    draft: draft,
                    onChanged: () => setState(() {}),
                  ),
                );
              }),
              if (drafts.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isSaving ? null : _saveExisting,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      isSaving ? 'กำลังบันทึก...' : 'บันทึก',
                      style: AppTextStyles.button.copyWith(color: Colors.white),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryLight : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(sublabel, style: AppTextStyles.caption),
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
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
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
          ),
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
