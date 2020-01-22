import 'dart:async';
import 'dart:html';

import 'package:angular/angular.dart';
import 'package:angular/src/runtime.dart' show unsafeCast;
import 'package:angular/src/core/change_detection/differs/default_iterable_differ.dart';

import '../collections/data_source.dart';
import 'cell.dart';
import 'row.dart';

/// Interface used to provide an outlet for rows to be inserted into.
abstract class RowOutlet {
  ViewContainerRef viewContainer;
}

/// Provides a handle for the table to grab the view container's ng-container to insert data rows.
@Directive(selector: '[rowOutlet]')
class DataRowOutlet implements RowOutlet {
  @override
  ViewContainerRef viewContainer;

  DataRowOutlet(this.viewContainer);
}

/// Provides a handle for the table to grab the view container's ng-container to insert the header.
@Directive(selector: '[headerRowOutlet]')
class HeaderRowOutlet implements RowOutlet {
  @override
  ViewContainerRef viewContainer;

  HeaderRowOutlet(this.viewContainer);
}

/// Provides a handle for the table to grab the view container's ng-container to insert the footer.
@Directive(selector: '[footerRowOutlet]')
class FooterRowOutlet implements RowOutlet {
  @override
  ViewContainerRef viewContainer;

  FooterRowOutlet(this.viewContainer);
}

const pdkTableTemplate = '''
  <ng-content select="caption"></ng-content>
  <template headerRowOutlet></template>
  <template rowOutlet></template>
  <template footerRowOutlet></template>
''';

/// Set of properties that represents the identity of a single rendered row.
///
/// When the table needs to determine the list of rows to render, it will do so by iterating through
/// each data object and evaluating its list of row templates to display (when multiTemplateDataRows
/// is false, there is only one template per data object). For each pair of data object and row
/// template, a `RenderRow` is added to the list of rows to render. If the data object and row
/// template pair has already been rendered, the previously used `RenderRow` is added; else a new
/// `RenderRow` is * created. Once the list is complete and all data objects have been itereated
/// through, a diff is performed to determine the changes that need to be made to the rendered rows.
class RenderRow<T> {
  final T data;
  final PdkRowDef<T> rowDef;
  int dataIndex;

  RenderRow(this.data, this.dataIndex, this.rowDef);
}

/// A data table that can render a header row, data rows, and a footer row.
/// Uses the dataSource input to determine the data to be rendered. The data can be provided either
/// as a data array, an Observable stream that emits the data array to render, or a DataSource with a
/// connect function that will return an Observable stream that emits the data array to render.
@Component(
  selector: 'pdk-table',
  exportAs: 'pdkTable',
  template: pdkTableTemplate,
  encapsulation: ViewEncapsulation.None,
  // The "OnPush" status for the `PdkTable` component is effectively a noop, so we are removing it.
  // The view for `PdkTable` consists entirely of templates declared in other views. As they are
  // declared elsewhere, they are checked when their declaration points are checked.
  changeDetection: ChangeDetectionStrategy.Default,
  directives: [
    DataRowOutlet,
    HeaderRowOutlet,
    FooterRowOutlet,
  ]
)
class PdkTable<T> implements AfterContentChecked, OnDestroy, OnInit {
  /// Latest data provided by the data source.
  List<T> _data;

  /// List of the rendered rows as identified by their `RenderRow` object.
  List<RenderRow<T>> _renderRows;

  /// Subscription that listens for the data provided by the data source.
  StreamSubscription _renderChangeSubscription;

  /// Map of all the user's defined columns (header, data, and footer cell template) identified by
  /// name. Collection populated by the column definitions gathered by `ContentChildren` as well as
  /// any custom column definitions added to `_customColumnDefs`.
  final _columnDefsByName = <String, PdkColumnDef>{};

  /// Set of all row definitions that can be used by this table. Populated by the rows gathered by
  /// using `ContentChildren` as well as any custom row definitions added to `_customRowDefs`.
  List<PdkRowDef<T>> _rowDefs;

  /// Set of all header row definitions that can be used by this table. Populated by the rows
  /// gathered by using `ContentChildren` as well as any custom row definitions added to
  /// `_customHeaderRowDefs`.
  List<PdkHeaderRowDef> _headerRowDefs;

  /// Set of all row definitions that can be used by this table. Populated by the rows gathered by
  /// using `ContentChildren` as well as any custom row definitions added to
  /// `_customFooterRowDefs`.
  List<PdkFooterRowDef> _footerRowDefs;

  /// Stores the row definition that does not have a when predicate.
  PdkRowDef<T> _defaultRowDef;

  /// Column definitions that were defined outside of the direct content children of the table.
  /// These will be defined when, e.g., creating a wrapper around the pdkTable that has
  /// column definitions as *its* content child.
  final _customColumnDefs = <PdkColumnDef>{};

  /// Data row definitions that were defined outside of the direct content children of the table.
  /// These will be defined when, e.g., creating a wrapper around the pdkTable that has
  /// built-in data rows as *its* content child.
  final _customRowDefs = <PdkRowDef<T>>{};

  /// Header row definitions that were defined outside of the direct content children of the table.
  /// These will be defined when, e.g., creating a wrapper around the pdkTable that has
  /// built-in header rows as *its* content child.
  final _customHeaderRowDefs = <PdkHeaderRowDef>{};

  /// Footer row definitions that were defined outside of the direct content children of the table.
  /// These will be defined when, e.g., creating a wrapper around the pdkTable that has a
  /// built-in footer row as *its* content child.
  final _customFooterRowDefs = <PdkFooterRowDef>{};

  /// Whether the header row definition has been changed. Triggers an update to the header row after
  /// content is checked. Initialized as true so that the table renders the initial set of rows.
  var _headerRowDefChanged = true;

  /// Whether the footer row definition has been changed. Triggers an update to the footer row after
  /// content is checked. Initialized as true so that the table renders the initial set of rows.
  var _footerRowDefChanged = true;

  /// Cache of the latest rendered `RenderRow` objects as a map for easy retrieval when constructing
  /// a new list of `RenderRow` objects for rendering rows. Since the new list is constructed with
  /// the cached `RenderRow` objects when possible, the row identity is preserved when the data
  /// and row template matches, which allows the `IterableDiffer` to check rows by reference
  /// and understand which rows are added/moved/removed.
  ///
  /// Implemented as a map of maps where the first key is the `data: T` object and the second is the
  /// `PdkRowDef<T>` object. With the two keys, the cache points to a `RenderRow<T>` object that
  /// contains an array of created pairs. The array is necessary to handle cases where the data
  /// array contains multiple duplicate data objects and each instantiated `RenderRow` must be
  /// stored.
  var _cachedRenderRowsMap = <T, Map<PdkRowDef<T>, List<RenderRow<T>>>>{};

  // Stream that emits when the component has been destroyed.
  final _onDestroyController = StreamController<void>();

  /// Tracking function that will be used to check the differences in data changes. Used similarly
  /// to `ngFor` `trackBy` function. Optimize row operations by identifying a row based on its data
  /// relative to the function to know if a row should be added/removed/moved.
  /// Accepts a function that takes two parameters, `index` and `item`.
  @Input()
  TrackByFn trackBy;

  /// Differ used to find the changes in the data provided by the data source.
  DefaultIterableDiffer _dataDiffer;

  /// The table's source of data, which can be provided in three ways (in order of complexity):
  ///   - Simple data array (each object represents one table row)
  ///   - Stream that emits a data array each time the array changes
  ///   - `DataSource` object that implements the connect/disconnect interface.
  ///
  /// If a data array is provided, the table must be notified when the array's objects are
  /// added, removed, or moved. This can be done by calling the `renderRows()` function which will
  /// render the diff since the last table render. If the data array reference is changed, the table
  /// will automatically trigger an update to the rows.
  ///
  /// When providing an Observable stream, the table will trigger an update automatically when the
  /// stream emits a new array of data.
  ///
  /// Finally, when providing a `DataSource` object, the table will use the Observable stream
  /// provided by the connect function and trigger updates when that stream emits new data array
  /// values. During the table's ngOnDestroy or when the data source is removed from the table, the
  /// table will call the DataSource's `disconnect` function (may be useful for cleaning up any
  /// subscriptions registered during the connect process).
  DataSource<T> get dataSource {
    return _dataSource;
  }

  @Input()
  set dataSource(DataSource<T> dataSource) {
    if (_dataSource != dataSource) {
      _switchDataSource(dataSource);
    }
  }

  DataSource<T> _dataSource;

  /// Whether to allow multiple rows per data object by evaluating which rows evaluate their 'when'
  /// predicate to true. If `multiTemplateDataRows` is false, which is the default value, then each
  /// dataobject will render the first row that evaluates its when predicate to true, in the order
  /// defined in the table, or otherwise the default row which does not have a when predicate.
  bool get multiTemplateDataRows {
    return _multiTemplateDataRows;
  }

  @Input()
  set multiTemplateDataRows(bool multiTemplate) {
    _multiTemplateDataRows = multiTemplate;

    if (rowOutlet != null && rowOutlet.viewContainer.length > 0) {
      _forceRenderDataRows();
    }
  }

  var _multiTemplateDataRows = false;


  @ViewChild(DataRowOutlet)
  DataRowOutlet rowOutlet;

  @ViewChild(HeaderRowOutlet)
  HeaderRowOutlet headerRowOutlet;

  @ViewChild(FooterRowOutlet)
  FooterRowOutlet footerRowOutlet;

  /// The column definitions provided by the user that contain what the header, data, and footer
  /// cells should render for each column.
  @ContentChildren(PdkColumnDef, descendants: true)
  List<PdkColumnDef> contentColumnDefs;

  /// Set of data row definitions that were provided to the table as content children.
  @ContentChildren(PdkRowDef, descendants: true)
  List<PdkRowDef<T>> contentRowDefs;

  /// Set of header row definitions that were provided to the table as content children.
  @ContentChildren(PdkHeaderRowDef, descendants: true)
  List<PdkHeaderRowDef> contentHeaderRowDefs;

  /// Set of footer row definitions that were provided to the table as content children.
  @ContentChildren(PdkFooterRowDef, descendants: true)
  List<PdkFooterRowDef> contentFooterRowDefs;

  final ChangeDetectorRef _changeDetectorRef;
  final Element _element;

  PdkTable(this._changeDetectorRef, this._element, @Attribute('role') String role) {
    if (role == null) {
      _element.setAttribute('role', 'grid');
    }

    _element.classes.add('pdk-table');
  }

  @override
  void ngOnInit() {
    _dataDiffer = DefaultIterableDiffer((int index, dynamic item) {
      var dataRow = unsafeCast<RenderRow<T>>(item);
      return trackBy != null
          ? trackBy(dataRow.dataIndex, dataRow.data)
          : dataRow;
    });
  }

  @override
  void ngAfterContentChecked() {
    // Cache the row and column definitions gathered by ContentChildren and programmatic injection.
    _cacheRowDefs();
    _cacheColumnDefs();

    // Make sure that the user has at least added header, footer, or data row def.
    if (_headerRowDefs.isEmpty && _footerRowDefs.isEmpty && _rowDefs.isEmpty) {
      throw Exception('Missing definitions for header, footer, and row; '
          'cannot determine which columns should be rendered.');
    }

    // Render updates if the list of columns have been changed for the header, row, or footer defs.
    _renderUpdatedColumns();

     // If the header row definition has been changed, trigger a render to the header row.
    if (_headerRowDefChanged) {
      _forceRenderHeaderRows();
      _headerRowDefChanged = false;
    }

    // If the footer row definition has been changed, trigger a render to the footer row.
    if (_footerRowDefChanged) {
      _forceRenderFooterRows();
      _footerRowDefChanged = false;
    }

    // If there is a data source and row definitions, connect to the data source unless a
    // connection has already been made.
    if (dataSource != null &&
        _rowDefs.isNotEmpty &&
        _renderChangeSubscription == null) {
      _observeRenderChanges();
    }
  }

  @override
  void ngOnDestroy() {
    rowOutlet.viewContainer.clear();
    headerRowOutlet.viewContainer.clear();
    footerRowOutlet.viewContainer.clear();

    _cachedRenderRowsMap.clear();

    _onDestroyController.add(null);
    _onDestroyController.close();

    dataSource.disconnect();
  }

  /// Renders rows based on the table's latest set of data, which was either provided directly as an
  /// input or retrieved through an Observable stream (directly or from a DataSource).
  /// Checks for differences in the data since the last diff to perform only the necessary
  /// changes (add/remove/move rows).
  ///
  /// If the table's data source is a DataSource or Observable, this will be invoked automatically
  /// each time the provided Observable stream emits a new data array. Otherwise if your data is
  /// an array, this function will need to be called to render any changes.
  void renderRows() {
    _renderRows = _getAllRenderRows();
    final changes = _dataDiffer.diff(_renderRows);
    if (changes == null) {
      return;
    }

    final viewContainer = rowOutlet.viewContainer;

    changes.forEachOperation(
        (CollectionChangeRecord record, int prevIndex, int currentIndex) {
      if (record.previousIndex == null) {
        _insertRow(record.item, currentIndex);
      } else if (currentIndex == null) {
        viewContainer.remove(prevIndex);
      } else {
        final view = unsafeCast<EmbeddedViewRef>(viewContainer.get(prevIndex));
        viewContainer.move(view, currentIndex);
      }
    });

    // Update the meta context of a row's context data (index, count, first, last, ...)
    _updateRowIndexContext();

    // Update rows that did not get added/removed/moved but may have had their identity changed,
    // e.g. if trackBy matched data on some property but the actual data reference changed.
    changes.forEachIdentityChange((CollectionChangeRecord record) {
      final rowView = unsafeCast<EmbeddedViewRef>(viewContainer.get(record.currentIndex));
      rowView.setLocal('\$implicit', record.item.data);
    });
  }

  /// Adds a column definition that was not included as part of the content children.
  void addColumnDef(PdkColumnDef columnDef) {
    _customColumnDefs.add(columnDef);
  }

  /// Removes a column definition that was not included as part of the content children.
  void removeColumnDef(PdkColumnDef columnDef) {
    _customColumnDefs.remove(columnDef);
  }

  /// Adds a row definition that was not included as part of the content children.
  void addRowDef(PdkRowDef<T> rowDef) {
    _customRowDefs.add(rowDef);
  }

  /// Removes a row definition that was not included as part of the content children.
  void removeRowDef(PdkRowDef<T> rowDef) {
    _customRowDefs.remove(rowDef);
  }

  /// Adds a header row definition that was not included as part of the content children.
  void addHeaderRowDef(PdkHeaderRowDef headerRowDef) {
    _customHeaderRowDefs.add(headerRowDef);
    _headerRowDefChanged = true;
  }

  /// Removes a header row definition that was not included as part of the content children.
  void removeHeaderRowDef(PdkHeaderRowDef headerRowDef) {
    _customHeaderRowDefs.remove(headerRowDef);
    _headerRowDefChanged = true;
  }

  /// Adds a footer row definition that was not included as part of the content children.
  void addFooterRowDef(PdkFooterRowDef footerRowDef) {
    _customFooterRowDefs.add(footerRowDef);
    _footerRowDefChanged = true;
  }

  /// Removes a footer row definition that was not included as part of the content children.
  void removeFooterRowDef(PdkFooterRowDef footerRowDef) {
    _customFooterRowDefs.remove(footerRowDef);
    _footerRowDefChanged = true;
  }

  /// Get the list of RenderRow objects to render according to the current list of data and defined
  /// row definitions. If the previous list already contained a particular pair, it should be reused
  /// so that the differ equates their references.
  List<RenderRow<T>> _getAllRenderRows() {
    final renderRows = <RenderRow<T>>[];

    // Store the cache and create a new one. Any re-used RenderRow objects will be moved into the
    // new cache while unused ones can be picked up by garbage collection.
    final prevCachedRenderRows = _cachedRenderRowsMap;
    _cachedRenderRowsMap = {};

    // For each data object, get the list of rows that should be rendered, represented by the
    // respective `RenderRow` object which is the pair of `data` and `PdkRowDef`.
    for (var i = 0; i < _data.length; i++) {
      final data = _data[i];
      final renderRowsForData =
          _getRenderRowsForData(data, i, prevCachedRenderRows[data]);

      if (!_cachedRenderRowsMap.containsKey(data)) {
        _cachedRenderRowsMap[data] = {};
      }

      for (var j = 0; j < renderRowsForData.length; j++) {
        final renderRow = renderRowsForData[j];

        final cache = _cachedRenderRowsMap[renderRow.data];
        if (cache.containsKey(renderRow.rowDef)) {
          cache[renderRow.rowDef].add(renderRow);
        } else {
          cache[renderRow.rowDef] = [renderRow];
        }
        renderRows.add(renderRow);
      }
    }

    return renderRows;
  }

  /// Gets a list of `RenderRow<T>` for the provided data object and any `PdkRowDef` objects that
  /// should be rendered for this data. Reuses the cached RenderRow objects if they match the same
  /// `(T, PdkRowDef)` pair.
  List<RenderRow<T>> _getRenderRowsForData(T data, int dataIndex,
      [Map<PdkRowDef<T>, List<RenderRow<T>>> cache]) {
    final rowDefs = _getRowDefs(data, dataIndex);

    return rowDefs.map((rowDef) {
      final cachedRenderRows = (cache != null && cache.containsKey(rowDef))
          ? cache[rowDef]
          : <RenderRow<T>>[];
      if (cachedRenderRows.isNotEmpty) {
        final dataRow = cachedRenderRows.removeAt(0);
        return dataRow..dataIndex = dataIndex;
      } else {
        return RenderRow<T>(data, dataIndex, rowDef);
      }
    }).toList();
  }

  /// Update the map containing the content's column definitions.
  void _cacheColumnDefs() {
    _columnDefsByName.clear();

    final columnDefs = [...contentColumnDefs, ..._customColumnDefs];
    columnDefs.forEach((columnDef) {
      if (_columnDefsByName.containsKey(columnDef.name)) {
        throw Exception(
            'Duplicate column definition name provided: "${columnDef.name}".');
      }
      _columnDefsByName[columnDef.name] = columnDef;
    });
  }

  /// Update the list of all available row definitions that can be used.
  void _cacheRowDefs() {
    _headerRowDefs = [...contentHeaderRowDefs, ..._customHeaderRowDefs];
    _footerRowDefs = [...contentFooterRowDefs, ..._customFooterRowDefs];
    _rowDefs = [...contentRowDefs, ..._customRowDefs];

    // After all row definitions are determined, find the row definition to be considered default.
    final defaultRowDefs = _rowDefs.where((def) => def.when == null);
    if (!multiTemplateDataRows && defaultRowDefs.length > 1) {
      throw Exception(
          'There can only be one default row without a when predicate function.');
    }
    _defaultRowDef = defaultRowDefs.first;
  }

  /// Check if the header, data, or footer rows have changed what columns they want to display.
  /// If there is a diff, then re-render that section.
  void _renderUpdatedColumns() {
    bool columnsDiffReducer(bool acc, BaseRowDef def) =>
        acc || def.getColumnsDiff() != null;

    // Force re-render data rows if the list of column definitions have changed.
    if (_rowDefs.fold(false, columnsDiffReducer)) {
      _forceRenderDataRows();
    }

    // Force re-render header/footer rows if the list of column definitions have changed..
    if (_headerRowDefs.fold(false, columnsDiffReducer)) {
      _forceRenderHeaderRows();
    }

    if (_footerRowDefs.fold(false, columnsDiffReducer)) {
      _forceRenderFooterRows();
    }
  }

  /// Switch to the provided data source by resetting the data and unsubscribing from the current
  /// render change subscription if one exists. If the data source is null, interpret this by
  /// clearing the row outlet. Otherwise start listening for new data.
  void _switchDataSource(DataSource<T> dataSource) {
    _data = [];
    dataSource.disconnect();

    // Stop listening for data from the previous data source.
    if (_renderChangeSubscription != null) {
      _renderChangeSubscription.cancel();
      _renderChangeSubscription = null;
    }

    if (dataSource == null) {
      if (_dataDiffer != null) {
        _dataDiffer.diff([]);
      }
      rowOutlet.viewContainer.clear();
    }

    _dataSource = dataSource;
  }

  /// Set up a subscription for the data provided by the data source.
  void _observeRenderChanges() {
    // If no data source has been set, there is nothing to observe for changes.
    if (dataSource == null) {
      return;
    }

    var dataStream = dataSource.connect();

    _renderChangeSubscription = dataStream.listen((data) {
      if (data == null) {
        _data = [];
      } else {
        _data = data;
      }
      renderRows();
    });
  }

  /// Clears any existing content in the header row outlet and creates a new embedded view
  /// in the outlet using the header row definition.
  void _forceRenderHeaderRows() {
    // Clear the header row outlet if any content exists.
    if (headerRowOutlet.viewContainer.length > 0) {
      headerRowOutlet.viewContainer.clear();
    }

    for (var i = 0; i < _headerRowDefs.length; i++) {
      _renderRow(headerRowOutlet, _headerRowDefs[i], i);
    }
  }

  /// Clears any existing content in the footer row outlet and creates a new embedded view
  /// in the outlet using the footer row definition.
  void _forceRenderFooterRows() {
    // Clear the footer row outlet if any content exists.
    if (footerRowOutlet.viewContainer.length > 0) {
      footerRowOutlet.viewContainer.clear();
    }

    for (var i = 0; i < _footerRowDefs.length; i++) {
      _renderRow(footerRowOutlet, _footerRowDefs[i], i);
    }
  }

  /// Get the matching row definitions that should be used for this row data. If there is only
  /// one row definition, it is returned. Otherwise, find the row definitions that has a when
  /// predicate that returns true with the data. If none return true, return the default row
  /// definition.
  List<PdkRowDef<T>> _getRowDefs(T data, int dataIndex) {
    if (_rowDefs.length == 1) {
      return [_rowDefs.first];
    }

    var rowDefs = <PdkRowDef<T>>[];
    if (multiTemplateDataRows) {
      rowDefs = _rowDefs
          .takeWhile((def) => def.when == null || def.when(dataIndex, data));
    } else {
      final rowDef = _rowDefs.firstWhere(
          (def) => def.when != null && def.when(dataIndex, data),
          orElse: () => _defaultRowDef);
      if (rowDef != null) {
        rowDefs.add(rowDef);
      }
    }

    if (rowDefs.isEmpty) {
      throw Exception(
          'Could not find a matching row definition for the provided row data: $data');
    }

    return rowDefs;
  }

  /// Create the embedded view for the data row template and place it in the correct index location
  /// within the data row view container.
  void _insertRow(RenderRow<T> renderRow, int renderIndex) {
    final rowDef = renderRow.rowDef;
    final context = <String, T>{'\$implicit': renderRow.data};
    _renderRow(rowOutlet, rowDef, renderIndex, context);
  }

  /// Creates a new row template in the outlet and fills it with the set of cell templates.
  /// Optionally takes a context to provide to the row and cells, as well as an optional index
  /// of where to place the new row template in the outlet.
  void _renderRow(RowOutlet outlet, BaseRowDef rowDef, int index,
      [Map<String, dynamic> context]) {
    var embeddedRef =
        outlet.viewContainer.insertEmbeddedView(rowDef.template, index);
    context?.forEach(embeddedRef.setLocal);

    for (var cellTemplate in _getCellTemplates(rowDef)) {
      if (PdkCellOutlet.mostRecentCellOutlet != null) {
        embeddedRef = PdkCellOutlet.mostRecentCellOutlet.viewContainer
            .createEmbeddedView(cellTemplate);
        context?.forEach(embeddedRef.setLocal);
      }
    }

    _changeDetectorRef.markForCheck();
  }

  /// Updates the index-related context for each row to reflect any changes in the index of the rows,
  /// e.g. first/last/even/odd.
  void _updateRowIndexContext() {
    final viewContainer = rowOutlet.viewContainer;
    for (var renderIndex = 0, count = viewContainer.length;
        renderIndex < count;
        renderIndex++) {
      final viewRef = unsafeCast<EmbeddedViewRef>(viewContainer.get(renderIndex));
      viewRef.setLocal('count', count);
      viewRef.setLocal('first', renderIndex == 0);
      viewRef.setLocal('last', renderIndex == count - 1);
      viewRef.setLocal('even', renderIndex % 2 == 0);
      viewRef.setLocal('odd', renderIndex % 2 != 0);

      if (multiTemplateDataRows) {
        viewRef.setLocal('dataIndex', _renderRows[renderIndex].dataIndex);
        viewRef.setLocal('renderIndex', renderIndex);
      } else {
        viewRef.setLocal('index', _renderRows[renderIndex].dataIndex);
      }
    }
  }

  /// Gets the column definitions for the provided row def.
  List<TemplateRef> _getCellTemplates(BaseRowDef rowDef) {
    if (rowDef == null || rowDef.columns == null || rowDef.columns.isEmpty) {
      return [];
    }
    return rowDef.columns.map((columnId) {
      final column = _columnDefsByName[columnId];

      if (column == null) {
        throw Exception('Could not find column with id "$columnId".');
      }

      return rowDef.extractCellTemplate(column);
    }).toList();
  }

  /// Forces a re-render of the data rows. Should be called in cases where there has been an input
  /// change that affects the evaluation of which rows should be rendered, e.g. toggling
  /// `multiTemplateDataRows` or adding/removing row definitions.
  void _forceRenderDataRows() {
    _dataDiffer.diff([]);
    rowOutlet.viewContainer.clear();
    renderRows();
  }
}
