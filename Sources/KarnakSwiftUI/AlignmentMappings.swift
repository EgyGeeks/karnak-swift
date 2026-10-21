import KarnakCore
import SwiftUI

struct ColumnAlignment {
  let alignment: HorizontalAlignment
  let stretches: Bool
}

func columnAlignment(_ alignment: KarnakHorizontalAlignment) -> ColumnAlignment {
  switch alignment {
  case .center: ColumnAlignment(alignment: .center, stretches: false)
  case .end: ColumnAlignment(alignment: .trailing, stretches: false)
  case .stretch: ColumnAlignment(alignment: .leading, stretches: true)
  default: ColumnAlignment(alignment: .leading, stretches: false)
  }
}

struct RowAlignment {
  let alignment: VerticalAlignment
  let stretches: Bool
}

func rowAlignment(_ alignment: KarnakVerticalAlignment) -> RowAlignment {
  switch alignment {
  case .center: RowAlignment(alignment: .center, stretches: false)
  case .bottom: RowAlignment(alignment: .bottom, stretches: false)
  case .stretch: RowAlignment(alignment: .top, stretches: true)
  default: RowAlignment(alignment: .top, stretches: false)
  }
}

func stackAlignment(_ alignment: ContentAlignment) -> Alignment {
  switch alignment {
  case .topcenter: .top
  case .topend: .topTrailing
  case .centerstart: .leading
  case .center: .center
  case .centerend: .trailing
  case .bottomstart: .bottomLeading
  case .bottomcenter: .bottom
  case .bottomend: .bottomTrailing
  default: .topLeading
  }
}

func textAlignment(_ alignment: TextAlign) -> TextAlignment {
  switch alignment {
  case .center: .center
  case .end: .trailing
  default: .leading
  }
}
