import KarnakCore
import SwiftUI

/// The layout fields `column`, `form` and `row` share, mapped to the layouts' own types.
struct LinearFields {
  /// Gap between adjacent children, and between lines of a wrapping row.
  var spacing: CGFloat
  /// Main-axis arrangement.
  var arrangement: KarnakArrangement
  /// Cross-axis alignment.
  var alignment: KarnakCrossAlignment
  /// The container's own box.
  var layout: ResolvedLayout

  init(_ column: ResolvedColumn) {
    self.init(
      spacing: column.spacing, arrangement: column.arrangement,
      alignment: crossAlignment(column.horizontalAlignment), layout: column.layout)
  }

  init(_ form: ResolvedForm) {
    self.init(
      spacing: form.spacing, arrangement: form.arrangement,
      alignment: crossAlignment(form.horizontalAlignment), layout: form.layout)
  }

  init(_ row: ResolvedRow) {
    self.init(
      spacing: row.spacing, arrangement: row.arrangement,
      alignment: crossAlignment(row.verticalAlignment), layout: row.layout)
  }

  private init(
    spacing: Float, arrangement: Arrangement, alignment: KarnakCrossAlignment,
    layout: ResolvedLayout
  ) {
    self.spacing = points(dp: spacing)
    self.arrangement = karnakArrangement(arrangement)
    self.alignment = alignment
    self.layout = layout
  }
}

func karnakArrangement(_ arrangement: Arrangement) -> KarnakArrangement {
  switch arrangement {
  case .center: .center
  case .end: .end
  case .spacebetween: .spaceBetween
  case .spacearound: .spaceAround
  case .spaceevenly: .spaceEvenly
  default: .start
  }
}

func crossAlignment(_ alignment: KarnakHorizontalAlignment) -> KarnakCrossAlignment {
  switch alignment {
  case .center: .center
  case .end: .end
  case .stretch: .stretch
  default: .start
  }
}

func crossAlignment(_ alignment: KarnakSelfAlignment) -> KarnakCrossAlignment {
  switch alignment {
  case .center: .center
  case .end: .end
  case .stretch: .stretch
  default: .start
  }
}

func crossAlignment(_ alignment: KarnakVerticalAlignment) -> KarnakCrossAlignment {
  switch alignment {
  case .center: .center
  case .bottom: .end
  case .stretch: .stretch
  default: .start
  }
}
