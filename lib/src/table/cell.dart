import 'dart:html';

import 'package:angular/angular.dart';

/// Cell definition for a PDK table.
/// Captures the template of a column's data row cell as well as cell-specific properties.
@Directive(selector: '[pdkCellDef]')
class PdkCellDef {
  TemplateRef template;

  PdkCellDef(this.template);
}

/// Header cell definition for a PDK table.
/// Captures the template of a column's header cell and as well as cell-specific properties.
@Directive(selector: '[pdkHeaderCellDef]')
class PdkHeaderCellDef {
  TemplateRef template;

  PdkHeaderCellDef(this.template);
}

/// Footer cell definition for a PDK table.
/// Captures the template of a column's footer cell and as well as cell-specific properties.
@Directive(selector: '[pdkFooterCellDef]')
class PdkFooterCellDef {
  TemplateRef template;

  PdkFooterCellDef(this.template);
}

/// Column definition for the PDK table.
/// Defines a set of cells available for a table column.
@Directive(
  selector: 'pdk-column-def',
)
class PdkColumnDef {
  String get name {
    return _name;
  }

  /// Unique name for this column.
  @Input()
  set name(String name) {
    // If the directive is set without a name (updated programatically), then this setter will
    // trigger with an empty string and should not overwrite the programatically set value.
    if (name == null || name.isEmpty) {
      return;
    }

    _name = name;
    cssClassFriendlyName =
        name.replaceAll(RegExp(r'[^a-z0-9_-]', caseSensitive: false), '-');
  }

  String _name;

  @ContentChild(PdkCellDef)
  PdkCellDef cell;

  @ContentChild(PdkHeaderCellDef)
  PdkHeaderCellDef headerCell;

  @ContentChild(PdkFooterCellDef)
  PdkFooterCellDef footerCell;

  /// Transformed version of the column name that can be used as part of a CSS classname. Excludes
  /// all non-alphanumeric characters and the special characters '-' and '_'. Any characters that
  /// do not match are replaced by the '-' character.
  String cssClassFriendlyName;
}

/// Base class for the cells. Adds a CSS classname that identifies the column it renders in.
class BasePdkCell {
  BasePdkCell(PdkColumnDef columnDef, Element element) {
    final columnClassName = 'pdk-column-${columnDef.cssClassFriendlyName}';
    element.classes.add(columnClassName);
  }
}

/// Header cell template container that adds the right classes and role.
@Directive(
  selector: 'pdk-header-cell, [pdkHeaderCell]',
)
class PdkHeaderCell extends BasePdkCell {
  PdkHeaderCell(@Host() PdkColumnDef columnDef, Element element)
      : super(columnDef, element) {
    element.classes.add('pdk-header-cell');
  }
}

/// Footer cell template container that adds the right classes and role.
@Directive(
  selector: 'pdk-footer-cell, [pdkFooterCell]',
)
class PdkFooterCell extends BasePdkCell {
  PdkFooterCell(@Host() PdkColumnDef columnDef, Element element)
      : super(columnDef, element) {
    element.classes.add('pdk-footer-cell');
  }
}

/// Cell template container that adds the right classes and role.
@Directive(
  selector: 'pdk-cell, [pdkCell]',
)
class PdkCell extends BasePdkCell {
  PdkCell(@Host() PdkColumnDef columnDef, Element element) : super(columnDef, element) {
    element.classes.add('pdk-cell');
  }
}
