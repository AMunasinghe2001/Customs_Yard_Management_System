import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../core/theme.dart';

/// Helper function to create styled dropdown items with alternating colors and dividers
List<DropdownMenuItem<T>> _buildStyledDropdownItems<T>(
  List<DropdownMenuItem<T>> items,
  BuildContext context,
) {
  return List.generate(items.length, (index) {
    final item = items[index];
    final isEvenRow = index % 2 == 0;
    
    // Much more visible color alternation
    final backgroundColor = isEvenRow 
        ? const Color(0xFFFFFFFF) // Pure white
        : const Color(0xFFEFF3F8); // Light blue-gray
    
    return DropdownMenuItem<T>(
      value: item.value,
      enabled: item.enabled,
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
        child: Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: const Color(0xFFDDE4ED),
              width: 0.8,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          width: double.infinity,
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
            child: item.child,
          ),
        ),
      ),
    );
  });
}

/// Custom reusable dropdown widget with beautiful, consistent styling
class CustomDropdownField<T> extends StatefulWidget {
  final T? value;
  final String label;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;
  final bool isExpanded;
  final Widget? prefixIcon;
  final String? hintText;
  final bool isDense;

  const CustomDropdownField({
    required this.label,
    required this.items,
    this.value,
    this.onChanged,
    this.validator,
    this.isExpanded = true,
    this.prefixIcon,
    this.hintText,
    this.isDense = false,
    Key? key,
  }) : super(key: key);

  @override
  State<CustomDropdownField<T>> createState() => _CustomDropdownFieldState<T>();
}

class _CustomDropdownFieldState<T> extends State<CustomDropdownField<T>> {
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) => setState(() {}),
      focusNode: _focusNode,
      child: DropdownButtonFormField<T>(
        value: widget.value,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hintText,
          prefixIcon: widget.prefixIcon != null ? Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: widget.prefixIcon!,
          ) : null,
          prefixIconConstraints: widget.prefixIcon != null 
            ? const BoxConstraints() 
            : null,
          filled: true,
          fillColor: context.colors.fieldFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.colors.borderColor, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.colors.borderColor, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.colors.primaryGold, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.colors.dangerRed, width: 1.5),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.colors.dangerRed, width: 2),
          ),
          labelStyle: TextStyle(
            color: _focusNode.hasFocus 
              ? context.colors.primaryGold 
              : context.colors.textSecondary,
            fontWeight: _focusNode.hasFocus ? FontWeight.w600 : FontWeight.normal,
          ),
          ),
        dropdownColor: context.colors.cardDark,
        icon: Icon(
          Icons.arrow_drop_down_rounded,
          color: context.colors.primaryGold,
          size: 28,
        ),
        iconSize: 28,
        isExpanded: widget.isExpanded,
        isDense: widget.isDense,
        items: _buildStyledDropdownItems(widget.items, context),
        onChanged: widget.onChanged,
        validator: widget.validator,
        style: TextStyle(
          color: context.colors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Custom dropdown without form validation (for filters, etc.)
class CustomDropdown<T> extends StatefulWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final IconData? prefixIcon;
  final Color? backgroundColor;
  final double? height;
  final TextStyle? itemTextStyle;

  const CustomDropdown({
    required this.items,
    this.value,
    this.onChanged,
    this.label,
    this.prefixIcon,
    this.backgroundColor,
    this.height = 40,
    this.itemTextStyle,
    Key? key,
  }) : super(key: key);

  @override
  State<CustomDropdown<T>> createState() => _CustomDropdownState<T>();
}

class _CustomDropdownState<T> extends State<CustomDropdown<T>> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? context.colors.surfaceDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: context.colors.primaryGold.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: context.colors.primaryGold.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: widget.value,
          isDense: true,
          isExpanded: true,
          dropdownColor: context.colors.cardDark,
          icon: Icon(
            Icons.arrow_drop_down_rounded,
            color: context.colors.primaryGold,
            size: 20,
          ),
          items: _buildStyledDropdownItems(widget.items, context),
          onChanged: widget.onChanged,
          style: widget.itemTextStyle ?? TextStyle(
            color: context.colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Dropdown with inline label (for compact layouts)
class CompactDropdown<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String label;
  final IconData icon;
  final double? width;

  const CompactDropdown({
    required this.label,
    required this.icon,
    required this.items,
    this.value,
    this.onChanged,
    this.width,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.surfaceDark.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: context.colors.primaryGold.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: context.colors.primaryGold),
          const Gap(8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isDense: true,
                isExpanded: true,
                dropdownColor: context.colors.cardDark,
                icon: Icon(
                  Icons.arrow_drop_down,
                  color: context.colors.primaryGold,
                  size: 18,
                ),
                items: _buildStyledDropdownItems(items, context),
                onChanged: onChanged,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
