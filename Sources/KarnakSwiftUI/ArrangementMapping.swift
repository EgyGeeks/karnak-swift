import KarnakCore
import SwiftUI

// Space arrangements need a custom Layout; alignment alone would lose their semantics.
enum SpaceDistribution {
  case packed, between, around, evenly
}

struct MainAxisArrangement {
  let alignment: Alignment
  let distribution: SpaceDistribution
}

func mainAxisArrangement(_ arrangement: Arrangement) -> MainAxisArrangement {
  switch arrangement {
  case .center: MainAxisArrangement(alignment: .center, distribution: .packed)
  case .end: MainAxisArrangement(alignment: .bottomTrailing, distribution: .packed)
  case .spacebetween: MainAxisArrangement(alignment: .topLeading, distribution: .between)
  case .spacearound: MainAxisArrangement(alignment: .topLeading, distribution: .around)
  case .spaceevenly: MainAxisArrangement(alignment: .topLeading, distribution: .evenly)
  default: MainAxisArrangement(alignment: .topLeading, distribution: .packed)
  }
}
