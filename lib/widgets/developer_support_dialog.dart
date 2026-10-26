import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import '../core/otp_config.dart';
import '../core/providers.dart';
import '../core/theme.dart';

/// Modal dialog providing direct contact with the system developer
/// (Anushanga Munasinghe), direct WhatsApp messaging, and a system-driven
/// feedback / change request / bug report form with file attachments that
/// transmits directly to anushangamunasinghe@gmail.com via the system mailer.
class DeveloperSupportDialog extends ConsumerStatefulWidget {
  final String portalName;
  final Color? accent;

  const DeveloperSupportDialog({
    super.key,
    required this.portalName,
    this.accent,
  });

  @override
  ConsumerState<DeveloperSupportDialog> createState() =>
      _DeveloperSupportDialogState();
}

class _DeveloperSupportDialogState
    extends ConsumerState<DeveloperSupportDialog> {
  static const String _devName = 'Anushanga Munasinghe';
  static const String _devRole = 'Lead Software Engineer & System Developer';
  static const String _devPhone = '0788314247';
  static const String _devEmail = 'anushangamunasinghe@gmail.com';
  static const String _waNumber = '94788314247';

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _designationCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  final List<PlatformFile> _attachments = [];
  bool _isSending = false;
  String? _statusError;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(currentProfileProvider);
    if (profile != null) {
      _nameCtrl.text = profile.fullName;
      _designationCtrl.text = profile.postShortTitle.isNotEmpty
          ? '${profile.postShortTitle.toUpperCase()} - ${widget.portalName}'
          : widget.portalName;
      _emailCtrl.text = profile.username ?? '';
      _phoneCtrl.text = profile.mobileNumber ?? '';
    } else {
      _designationCtrl.text = widget.portalName;
    }
    _subjectCtrl.text =
        'System Feedback / Assistance Request - ${widget.portalName}';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _designationCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _subjectCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  void _openWhatsApp() {
    final senderName = _nameCtrl.text.trim();
    final prefix = senderName.isNotEmpty
        ? 'Hello Anushanga, I am $senderName from ${widget.portalName}.'
        : 'Hello Anushanga, regarding the Customs Yard Management System (${widget.portalName}):';
    final encoded = Uri.encodeComponent('$prefix ');
    final url = 'https://wa.me/$_waNumber?text=$encoded';
    if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', url], runInShell: true);
    } else if (Platform.isMacOS) {
      Process.run('open', [url]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [url]);
    }
  }

  Future<void> _pickFiles() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (res != null && res.files.isNotEmpty) {
        setState(() {
          _attachments.addAll(res.files.where((f) => f.path != null));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to select files: $e')),
        );
      }
    }
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSending = true;
      _statusError = null;
    });

    try {
      if (!kGmailConfigured) {
        throw Exception(
            'System mailer is not configured. Please check SMTP settings.');
      }

      final smtp = SmtpServer(
        'smtp.gmail.com',
        username: kGmailUser,
        password: kGmailAppPassword,
        port: 465,
        ssl: true,
      );

      final senderName = _nameCtrl.text.trim();
      final senderRole = _designationCtrl.text.trim();
      final senderPhone = _phoneCtrl.text.trim();
      final senderEmail = _emailCtrl.text.trim();
      final subjectText = _subjectCtrl.text.trim();
      final descText = _descriptionCtrl.text.trim();
      final dateStr = DateTime.now().toLocal().toString().split('.')[0];

      final htmlBody = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f0f4fa; color: #1e293b; margin: 0; padding: 30px 16px; }
    .card { background: #ffffff; max-width: 600px; margin: 0 auto; border-radius: 16px; overflow: hidden; box-shadow: 0 8px 30px rgba(14,12,58,0.12); }
    .header { background: linear-gradient(135deg, #231f87 0%, #1a1764 40%, #0e0c3a 100%); color: #ffffff; padding: 28px 30px 22px; position: relative; overflow: hidden; }
    .header::after { content: ''; position: absolute; top: -40px; right: -40px; width: 120px; height: 120px; background: rgba(212,160,23,0.08); border-radius: 50%; }
    .header::before { content: ''; position: absolute; bottom: -20px; left: 40%; width: 80px; height: 80px; background: rgba(107,103,217,0.06); border-radius: 50%; }
    .header h1 { margin: 0; font-size: 18px; font-weight: 700; letter-spacing: 0.3px; position: relative; z-index: 1; }
    .header p { margin: 5px 0 0 0; font-size: 12px; color: rgba(255,255,255,0.6); position: relative; z-index: 1; }
    .badge { display: inline-block; background: rgba(212,160,23,0.2); color: #D4A017; padding: 4px 12px; border-radius: 6px; font-size: 11px; font-weight: 700; margin-top: 12px; border: 1px solid rgba(212,160,23,0.3); letter-spacing: 0.5px; position: relative; z-index: 1; }
    .body { padding: 28px 30px; }
    .section-label { font-size: 10px; text-transform: uppercase; letter-spacing: 1px; color: #231f87; font-weight: 700; margin: 0 0 14px 0; padding-bottom: 8px; border-bottom: 2px solid #f0f4fa; }
    .info-row { display: flex; padding: 10px 0; border-bottom: 1px solid #f8f9fc; }
    .info-label { width: 130px; font-size: 12px; font-weight: 600; color: #78909c; flex-shrink: 0; }
    .info-val { font-size: 13px; color: #0e0c3a; font-weight: 600; }
    .info-val a { color: #231f87; text-decoration: none; }
    .desc-section { margin-top: 24px; }
    .desc-label { font-size: 10px; text-transform: uppercase; letter-spacing: 1px; color: #231f87; font-weight: 700; margin: 0 0 10px 0; }
    .desc-box { background: linear-gradient(135deg, #f8f9fc 0%, #f0f4fa 100%); border-left: 3px solid #D4A017; padding: 16px 18px; border-radius: 0 10px 10px 0; font-size: 13px; line-height: 1.7; color: #334155; white-space: pre-wrap; }
    .footer { background: #f8f9fc; border-top: 1px solid #f0f4fa; padding: 18px 30px; text-align: center; }
    .footer p { margin: 0; font-size: 11px; color: #94a3b8; }
    .footer a { color: #231f87; text-decoration: none; font-weight: 600; }
    .att-badge { display: inline-block; background: #f0f4fa; color: #231f87; padding: 3px 10px; border-radius: 5px; font-size: 11px; font-weight: 600; border: 1px solid #e2e2e6; }
  </style>
</head>
<body>
  <div class="card">
    <div class="header" style="text-align:center;">
      <img src="https://upload.wikimedia.org/wikipedia/en/thumb/6/6c/Sri_Lanka_Customs_logo.svg/500px-Sri_Lanka_Customs_logo.svg.png"
           alt="Sri Lanka Customs"
           width="64"
           style="display:block;margin:0 auto 10px;width:64px;height:auto;border:0;outline:none;" />
      <h1>Sri Lanka Customs &mdash; CYMS</h1>
      <p>System Support &amp; Enhancement Request</p>
      <span class="badge">${widget.portalName}</span>
    </div>
    <div class="body">
      <p class="section-label">Sender Information</p>
      <div class="info-row"><span class="info-label">Name</span><span class="info-val">$senderName</span></div>
      <div class="info-row"><span class="info-label">Designation</span><span class="info-val">$senderRole</span></div>
      <div class="info-row"><span class="info-label">Phone</span><span class="info-val"><a href="tel:$senderPhone">$senderPhone</a></span></div>
      <div class="info-row"><span class="info-label">Email</span><span class="info-val"><a href="mailto:$senderEmail">$senderEmail</a></span></div>
      <div class="info-row"><span class="info-label">Submitted</span><span class="info-val">$dateStr</span></div>
      <div class="info-row"><span class="info-label">Subject</span><span class="info-val">$subjectText</span></div>
      <div class="info-row" style="border-bottom:none;"><span class="info-label">Attachments</span><span class="info-val"><span class="att-badge">${_attachments.length} file(s)</span></span></div>

      <div class="desc-section">
        <p class="desc-label">Message &amp; Description</p>
        <div class="desc-box">$descText</div>
      </div>
    </div>
    <div class="footer">
      <p>Dispatched via <strong>CYMS System Mailer</strong> to <a href="mailto:$_devEmail">$_devName</a></p>
    </div>
  </div>
</body>
</html>
''';

      final message = Message()
        ..from = Address(kGmailUser, '$senderName (CYMS System Support)')
        ..recipients.add(_devEmail)
        ..subject = '[CYMS Support] [${widget.portalName}] $subjectText'
        ..html = htmlBody;

      for (final att in _attachments) {
        if (att.path != null) {
          final file = File(att.path!);
          if (file.existsSync()) {
            message.attachments.add(FileAttachment(file, fileName: att.name));
          }
        }
      }

      await send(message, smtp);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.customsBlueDark,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            content: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_rounded,
                      color: context.colors.primaryGold, size: 18),
                ),
                const Gap(14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Request Dispatched Successfully',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 13)),
                      Text(
                          'Your message and attachments were sent to $_devName.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.7))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _statusError = 'Failed to dispatch email: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? context.colors.primaryGold;
    final isDark =
        Theme.of(context).brightness == Brightness.dark;

    final photoFile = File('developer_profile.jpg');
    final hasPhoto = photoFile.existsSync();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 760,
        constraints: const BoxConstraints(maxHeight: 740),
        decoration: BoxDecoration(
          color: context.colors.scaffoldBg,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 40,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header — same gradient as PackageDetailsDialog ──
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                gradient: widget.accent != null
                    ? LinearGradient(colors: [
                        widget.accent!.withOpacity(0.15),
                        context.colors.cardDark,
                      ])
                    : LinearGradient(
                        colors: isDark
                            ? [
                                context.colors.surfaceDark,
                                context.colors.cardDark
                              ]
                            : [
                                context.colors.customsBlue,
                                context.colors.customsBlueDark
                              ],
                      ),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Developer Photo — same icon-box style as the app
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: accent.withOpacity(0.6),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withOpacity(0.2),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: hasPhoto
                          ? Image.file(
                              photoFile,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _avatarFallback(accent),
                            )
                          : _avatarFallback(accent),
                    ),
                  ),
                  const Gap(16),
                  // Developer Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title row
                        Row(
                          children: [
                            Text(
                              _devName,
                              style: TextStyle(
                                color: _headerTextColor(isDark, widget.accent),
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Gap(10),
                            // Badge — same style as PackageDetailsDialog
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: accent.withOpacity(
                                    widget.accent != null ? 0.18 : 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: accent.withOpacity(
                                      widget.accent != null ? 0.5 : 0.4),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                'SYSTEM DEVELOPER',
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Gap(3),
                        Text(
                          _devRole,
                          style: TextStyle(
                            color: _headerSubTextColor(isDark, widget.accent),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Gap(8),
                        // Phone & Email — clear, visible chips
                        Row(
                          children: [
                            _contactChip(
                              icon: Icons.phone_in_talk_rounded,
                              text: _devPhone,
                              isDark: isDark,
                              hasAccent: widget.accent != null,
                            ),
                            const Gap(10),
                            Flexible(
                              child: _contactChip(
                                icon: Icons.email_rounded,
                                text: _devEmail,
                                isDark: isDark,
                                hasAccent: widget.accent != null,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Gap(10),
                  // Close
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded,
                        color: _headerSubTextColor(isDark, widget.accent),
                        size: 22),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            // ── Form Content ────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info banner
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: context.colors.fieldFill,
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: context.colors.borderColor),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 18, color: accent),
                            const Gap(10),
                            Expanded(
                              child: Text(
                                'Need system modifications, bug fixes, or guidance? Fill in the details below. '
                                'This form will automatically send an official alert directly to developer $_devName from the system.',
                                style: TextStyle(
                                  color: context.colors.textPrimary,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Gap(16),

                      // Row 1: Name & Designation
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _nameCtrl,
                              label: 'Your Name',
                              icon: Icons.person_outline_rounded,
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Name is required'
                                  : null,
                            ),
                          ),
                          const Gap(14),
                          Expanded(
                            child: _buildTextField(
                              controller: _designationCtrl,
                              label: 'Designation / Portal',
                              icon: Icons.badge_outlined,
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Designation is required'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const Gap(12),

                      // Row 2: Phone & Email
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _phoneCtrl,
                              label: 'Contact Phone Number',
                              icon: Icons.phone_outlined,
                            ),
                          ),
                          const Gap(14),
                          Expanded(
                            child: _buildTextField(
                              controller: _emailCtrl,
                              label: 'Your Email',
                              icon: Icons.alternate_email_rounded,
                            ),
                          ),
                        ],
                      ),
                      const Gap(12),

                      // Row 3: Subject
                      _buildTextField(
                        controller: _subjectCtrl,
                        label: 'Subject / Summary',
                        icon: Icons.title_rounded,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Subject is required'
                            : null,
                      ),
                      const Gap(12),

                      // Row 4: Description
                      _buildTextField(
                        controller: _descriptionCtrl,
                        label: 'Description / Required Changes / Questions',
                        icon: Icons.description_outlined,
                        maxLines: 4,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Please provide a description'
                            : null,
                      ),
                      const Gap(14),

                      // Attachments Section
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pickFiles,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: accent,
                              side:
                                  BorderSide(color: accent.withOpacity(0.5)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(Icons.attach_file_rounded,
                                size: 17),
                            label: const Text('Add Attachments / Screenshots',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ),
                          const Gap(12),
                          if (_attachments.isNotEmpty)
                            Text(
                              '${_attachments.length} file(s) attached',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: accent,
                                  fontWeight: FontWeight.w700),
                            ),
                        ],
                      ),

                      if (_attachments.isNotEmpty) ...[
                        const Gap(10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _attachments.map((file) {
                            final sizeKb =
                                ((file.size) / 1024).toStringAsFixed(1);
                            return Chip(
                              backgroundColor: context.colors.fieldFill,
                              side: BorderSide(
                                  color: context.colors.borderColor),
                              avatar: const Icon(
                                  Icons.insert_drive_file_outlined,
                                  size: 16),
                              label: Text('${file.name} ($sizeKb KB)',
                                  style: const TextStyle(fontSize: 11)),
                              deleteIcon:
                                  const Icon(Icons.close_rounded, size: 14),
                              onDeleted: () {
                                setState(() {
                                  _attachments.remove(file);
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],

                      if (_statusError != null) ...[
                        const Gap(12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color:
                                context.colors.dangerRed.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: context.colors.dangerRed
                                    .withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded,
                                  size: 18,
                                  color: context.colors.dangerRed),
                              const Gap(8),
                              Expanded(
                                child: Text(
                                  _statusError!,
                                  style: TextStyle(
                                      color: context.colors.dangerRed,
                                      fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // ── Dialog Footer Actions ───────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
              decoration: BoxDecoration(
                color: context.colors.fieldFill.withOpacity(0.5),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(24)),
                border: Border(
                  top: BorderSide(color: context.colors.borderColor),
                ),
              ),
              child: Row(
                children: [
                  _WhatsAppButton(onPressed: _openWhatsApp),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: _isSending
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const Gap(12),
                  FilledButton.icon(
                    onPressed: _isSending ? null : _submitRequest,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: _isSending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 16),
                    label: Text(
                      _isSending ? 'Transmitting...' : 'Send to Developer',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────

  /// Header text colour: white on the full navy gradient, textPrimary on
  /// the tinted-accent variant used by directorate portals.
  Color _headerTextColor(bool isDark, Color? portalAccent) {
    if (portalAccent != null) return context.colors.textPrimary;
    return Colors.white;
  }

  Color _headerSubTextColor(bool isDark, Color? portalAccent) {
    if (portalAccent != null) return context.colors.textMuted;
    return Colors.white.withOpacity(0.65);
  }

  /// Small pill showing phone / email inside the header.
  Widget _contactChip({
    required IconData icon,
    required String text,
    required bool isDark,
    required bool hasAccent,
  }) {
    final fg = hasAccent
        ? context.colors.textPrimary
        : Colors.white;
    final bg = hasAccent
        ? context.colors.fieldFill
        : Colors.white.withOpacity(0.1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasAccent
              ? context.colors.borderColor
              : Colors.white.withOpacity(0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 13,
              color: hasAccent
                  ? context.colors.primaryGold
                  : context.colors.primaryGold),
          const Gap(5),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback(Color accent) => CircleAvatar(
        backgroundColor: accent.withOpacity(0.2),
        child: Text('AM',
            style: TextStyle(
                color: accent,
                fontWeight: FontWeight.bold,
                fontSize: 22)),
      );

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    final accent = widget.accent ?? context.colors.primaryGold;
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      style: TextStyle(color: context.colors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            TextStyle(color: context.colors.textMuted, fontSize: 12),
        prefixIcon:
            Icon(icon, size: 18, color: context.colors.textMuted),
        isDense: true,
        filled: true,
        fillColor: context.colors.fieldFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.colors.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.colors.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
    );
  }
}

/// Glossy WhatsApp call-to-action pill with authentic WhatsApp brand logo.
class _WhatsAppButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _WhatsAppButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF25D366), Color(0xFF128C7E)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF25D366).withOpacity(0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CustomPaint(
                    painter: _WhatsAppLogoPainter(),
                  ),
                ),
                const Gap(8),
                const Text(
                  'WhatsApp Direct',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Precise vector painter for the official WhatsApp phone-in-bubble logo.
class _WhatsAppLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Speech bubble outline
    final bubblePath = Path()
      ..moveTo(w * 0.5, 0)
      ..cubicTo(w * 0.82, 0, w, h * 0.18, w, h * 0.45)
      ..cubicTo(w, h * 0.72, w * 0.82, h * 0.9, w * 0.5, h * 0.9)
      ..cubicTo(w * 0.42, h * 0.9, w * 0.35, h * 0.88, w * 0.28, h * 0.84)
      ..lineTo(w * 0.05, h * 0.98)
      ..lineTo(w * 0.14, h * 0.76)
      ..cubicTo(w * 0.05, h * 0.67, 0, h * 0.56, 0, h * 0.45)
      ..cubicTo(0, h * 0.18, w * 0.18, 0, w * 0.5, 0)
      ..close();

    final bubblePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawPath(bubblePath, bubblePaint);

    // Inner phone icon in green
    final phonePaint = Paint()
      ..color = const Color(0xFF128C7E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;

    final phonePath = Path()
      ..moveTo(w * 0.35, h * 0.32)
      ..cubicTo(w * 0.32, h * 0.40, w * 0.42, h * 0.58, w * 0.58, h * 0.65)
      ..lineTo(w * 0.64, h * 0.59)
      ..cubicTo(w * 0.66, h * 0.57, w * 0.68, h * 0.58, w * 0.70, h * 0.61)
      ..lineTo(w * 0.76, h * 0.69)
      ..cubicTo(w * 0.78, h * 0.72, w * 0.76, h * 0.76, w * 0.71, h * 0.77)
      ..cubicTo(w * 0.55, h * 0.80, w * 0.25, h * 0.56, w * 0.23, h * 0.37)
      ..cubicTo(w * 0.22, h * 0.32, w * 0.27, h * 0.28, w * 0.30, h * 0.28)
      ..lineTo(w * 0.37, h * 0.32)
      ..close();

    final fillPaint = Paint()
      ..color = const Color(0xFF128C7E)
      ..style = PaintingStyle.fill;
    canvas.drawPath(phonePath, fillPaint);
    canvas.drawPath(phonePath, phonePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
