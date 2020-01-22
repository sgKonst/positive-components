import 'dart:html';

import 'package:angular/angular.dart';
import 'package:angular/src/core/change_detection/differs/default_iterable_differ.dart';

import 'cell.dart';

/// The row template that can be used by the mat-table. Should not be used outside of the
/// material library.
const pdkRowTemplate = '<template pdkCellOutlet></template>';

/// Base class for the PdkHeaderRowDef and PdkRowDef that handles checking their columns inputs
/// for changes and notifying the table.
abstract class BaseRowDef {
  /// The columns to be displayed on this row.
  List<String> get columns => _columns;
  set columns(List<String> columns) {
    _columns = columns;

    // Create a new columns differ if one does not yet exist. Initialize it based on initial value
    // of the columns property or an empty array if none is provided.
    if (_columnsDiffer == null) {
      _columnsDiffer = DefaultIterableDiffer();
      _columnsDiffer.diff(columns);
    }
  }
  Iterable<String> _columns;

  final TemplateRef template;

  /// Differ used to check if any changes were made to the columns. */
  DefaultIterableDiffer _columnsDiffer;

  BaseRowDef(this.template);

  /// Returns the difference between the current columns and the columns from the last diff, or null
  /// if there is no difference.
  DefaultIterableDiffer getColumnsDiff() {
    return _columnsDiffer.diff(columns);
  }

  /// Gets this row def's relevant cell template from the provided column def.
  TemplateRef extractCellTemplate(PdkColumnDef column) {
    if (this is PdkHeaderRowDef) {
      return column.headerCell.template;
    } else if (this is PdkFooterRowDef) {
      return column.footerCell.template;
    } else {
      return column.cell.template;
    }
  }
}

/// Header row definition for the PDK table.
/// Captures the header row's template and other header properties such as the columns to display.
@Directive(
  selector: '[pdkHeaderRowDef]',
)
class PdkHeaderRowDef extends BaseRowDef {
  @Input('pdkHeaderRowDef')
  set cols(List<String> cols) {
    columns = cols;
  }

  PdkHeaderRowDef(TemplateRef template) : super(template);
}

/// Footer row definition for the PDK table.
/// Captures the footer row's template and other footer properties such as the columns to display.
@Directive(
  selector: '[pdkFooterRowDef]',
)
class PdkFooterRowDef extends BaseRowDef {
  @Input('pdkHeaderRowDef')
  set cols(List<String> cols) {
    columns = cols;
  }

  PdkFooterRowDef(TemplateRef template) : super(template);
}

/// Data row definition for the PDK table.
/// Captures the header row's template and other row properties such as the columns to display and
/// a when predicate that describes when this row should be used.
@Directive(
  selector: '[pdkRowDef]',
)
class PdkRowDef<T> extends BaseRowDef {
  @Input('pdkRowDefColumns')
  set cols(List<String> cols) {
    columns = cols;
  }

  /// Function that should return true if this row template should be used for the provided index
  /// and row data. If left undefined, this row will be considered the default row template to use
  /// when no other when functions return true for the data.
  /// For every row, there must be at least one when function that passes or an undefined to default.
  @Input('pdkRowDefWhen')
  bool Function(int index, T rowData) when;

  PdkRowDef(TemplateRef template) : super(template);
}

/// Outlet for rendering cells inside of a row or header row.
@Directive(
  selector: '[pdkCellOutlet]',
)
class PdkCellOutlet implements OnDestroy {
  /// The ordered list of cells to render within this outlet's view container
  List<PdkCellDef> cells;
  ViewContainerRef viewContainer;

  /// Static property containing the latest constructed instance of this class.
  /// Used by the PDK table when each PdkHeaderRow and PdkRow component is created using
  /// createEmbeddedView. After one of these components are created, this property will provide
  /// a handle to provide that component's cells and context. After init, the PdkCellOutlet will
  /// construct the cells with the provided context.
  static PdkCellOutlet mostRecentCellOutlet;

  PdkCellOutlet(this.viewContainer) {
    PdkCellOutlet.mostRecentCellOutlet = this;
  }

  @override
  void ngOnDestroy() {
    // If this was the last outlet being rendered in the view, remove the reference
    // from the static property after it has been destroyed to avoid leaking memory.
    if (PdkCellOutlet.mostRecentCellOutlet == this) {
      PdkCellOutlet.mostRecentCellOutlet = null;
    }
  }
}

/// Header template container that contains the cell outlet. Adds the right class and role.
@Component(
  selector: 'pdk-header-row',
  template: pdkRowTemplate,
  // See note on PdkTable for explanation on why this uses the default change detection strategy.
  changeDetection: ChangeDetectionStrategy.Default,
  encapsulation: ViewEncapsulation.None,
  directives: [
    PdkCellOutlet,
  ]
)
class PdkHeaderRow {
  PdkHeaderRow(Element element) {
    element.classes.add('pdk-header-row');
    element.setAttribute('role', 'row');
  }
}

/// Footer template container that contains the cell outlet. Adds the right class and role.
@Component(
  selector: 'pdk-footer-row',
  template: pdkRowTemplate,
  // See note on PdkTable for explanation on why this uses the default change detection strategy.
  changeDetection: ChangeDetectionStrategy.Default,
  encapsulation: ViewEncapsulation.None,
  directives: [
    PdkCellOutlet,
  ]
)
class PdkFooterRow {
  PdkFooterRow(Element element) {
    element.classes.add('pdk-footer-row');
    element.setAttribute('role', 'row');
  }
}

/// Data row template container that contains the cell outlet. Adds the right class and role.
@Component(
  selector: 'pdk-row',
  template: pdkRowTemplate,
  // See note on PdkTable for explanation on why this uses the default change detection strategy.
  changeDetection: ChangeDetectionStrategy.Default,
  encapsulation: ViewEncapsulation.None,
  directives: [
    PdkCellOutlet,
  ]
)
class PdkRow {
  PdkRow(Element element) {
    element.classes.add('pdk-row');
    element.setAttribute('role', 'row');
  }
}
