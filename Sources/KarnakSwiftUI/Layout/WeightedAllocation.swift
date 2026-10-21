import Foundation

struct AxisBounds: Sendable {
  var minimum: CGFloat = 0
  var maximum: CGFloat = .infinity
  var touchTarget: CGFloat = 0

  func clamp(_ size: CGFloat) -> CGFloat {
    max(minimum, min(size, maximum))
  }

  /// The space a child with this measured size takes in its container.
  func occupied(_ size: CGFloat) -> CGFloat {
    max(clamp(size), touchTarget)
  }

  var lower: CGFloat { max(minimum, touchTarget) }
  var upper: CGFloat { max(maximum, touchTarget) }
}

struct AllocationInput: Sendable {
  var weight: CGFloat = 0
  var measured: CGFloat = 0
  var bounds = AxisBounds()
}

struct AllocatedSlot {
  var occupied: CGFloat
  var drawn: CGFloat
  var inset: CGFloat { (occupied - drawn) / 2 }
}

/// Uses resolved bounds (including the padding floor). A nil extent ignores weights.
func allocateSlots(
  _ inputs: [AllocationInput], extent: CGFloat?, spacing: CGFloat
) -> [AllocatedSlot] {
  var sizes = inputs.map { $0.bounds.occupied($0.measured) }
  if let extent, extent.isFinite {
    var active = inputs.indices.filter { inputs[$0].weight > 0 }
    let fixed = inputs.indices.filter { inputs[$0].weight <= 0 }.reduce(CGFloat.zero) {
      $0 + sizes[$1]
    }
    var remaining = extent - fixed - spacing * CGFloat(max(0, inputs.count - 1))
    while !active.isEmpty {
      let weight = active.reduce(CGFloat.zero) { $0 + inputs[$1].weight }
      let targets = active.map { max(remaining, 0) * inputs[$0].weight / weight }
      let clamped = zip(active, targets).map { index, target in
        max(inputs[index].bounds.lower, min(target, inputs[index].bounds.upper))
      }
      let violation = zip(clamped, targets).reduce(CGFloat.zero) { $0 + $1.0 - $1.1 }
      var next: [Int] = []
      for (offset, index) in active.enumerated() {
        let delta = clamped[offset] - targets[offset]
        if violation == 0 || (violation > 0 && delta > 0) || (violation < 0 && delta < 0) {
          sizes[index] = clamped[offset]
          remaining -= sizes[index]
        } else {
          next.append(index)
        }
      }
      active = next
    }
  }
  return zip(inputs, sizes).map { input, occupied in
    let weighted = extent?.isFinite == true && input.weight > 0
    return AllocatedSlot(
      occupied: occupied, drawn: input.bounds.clamp(weighted ? occupied : input.measured))
  }
}
