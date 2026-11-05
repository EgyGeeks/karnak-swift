import KarnakCore
import SwiftUI

/// `range_slider` (`docs/renderer-contract.md`, Inputs, `ResolvedRangeSlider`): the rail (`track`), the part of it between
/// the thumbs in the track's `content` colour, and two thumbs. The lower thumb sits at the leading edge, so a right-to-left
/// environment mirrors the whole slider: positions are leading paddings, and a drag is read against the layout direction.
/// A thumb moves in whole steps from `min`, never past the other, and one move sends one `rangeChange` with both numbers.
/// A drag works on the whole rail, which is the touch target: it takes the thumb nearest to where it starts (the lower one
/// when both sit at the end of the rail or the press is before them), so overlapping thumbs stay reachable.
/// Each thumb is a VoiceOver adjustable element named by the input and "Minimum" or "Maximum", with its value; swiping up
/// or down moves it a step. A disabled or read-only slider ignores drags and adjustments.
struct RangeSliderView: View {
  let slider: ResolvedRangeSlider
  let placement: ChildPlacement
  @State private var focusedThumb: Thumb?
  @State private var dragged: (thumb: Thumb, start: Double)?
  @Environment(\.karnakInputs) private var inputs
  @Environment(\.karnakInputFocus) private var focus
  @Environment(\.layoutDirection) private var direction

  private enum Thumb: Hashable { case lower, upper }

  var body: some View {
    let drawn = restyled(slider, for: focusedThumb != nil ? [.focused] : [])
    InputFrame(input: drawn, placement: placement, label: drawn.label, support: drawn.error) {
      rail(drawn)
        .partBox(drawn.control, alignment: .center)
        .accessibilityElement(children: .contain)
    }
    .onChange(of: focusedThumb != nil) {
      inputs.send(.focusChange(slider.key, $0))
      if $0 { focus.moved(to: slider.key.value) }
    }
    .onReceive(focus.moves) { if $0 != slider.key.value { focusedThumb = nil } }
    .onReceive(focus.requests) { key in
      if key == slider.key.value, focus.take(key) { focusedThumb = .lower }
    }
    .onAppear {
      if focus.take(slider.key.value) { focusedThumb = .lower }
    }
  }

  private func rail(_ drawn: ResolvedRangeSlider) -> some View {
    let thumbWidth = points(dp: drawn.thumb.width?.floatValue ?? 0)
    let thumbHeight = points(dp: drawn.thumb.height?.floatValue ?? 0)
    let railHeight = points(dp: drawn.track.height?.floatValue ?? 0)
    return GeometryReader { proxy in
      let travel = max(proxy.size.width - thumbWidth, 1)
      ZStack(alignment: .leading) {
        Color.clear.partBox(drawn.track, alignment: .center)
          .frame(maxWidth: .infinity, minHeight: railHeight, maxHeight: railHeight)
          .accessibilityHidden(true)
        if let active = drawn.track.content {
          Rectangle()
            .fill(resolvedColor(active))
            .frame(
              width: travel * (share(drawn.upper, drawn) - share(drawn.lower, drawn)),
              height: railHeight
            )
            .padding(.leading, thumbWidth / 2 + travel * share(drawn.lower, drawn))
            .accessibilityHidden(true)
        }
        thumb(.lower, drawn, travel: travel, size: CGSize(width: thumbWidth, height: thumbHeight))
        thumb(.upper, drawn, travel: travel, size: CGSize(width: thumbWidth, height: thumbHeight))
      }
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
      .contentShape(Rectangle())
      .gesture(drag(drawn, travel: travel, thumbWidth: thumbWidth))
    }
    .frame(height: max(points(dp: drawn.control.minHeight?.floatValue ?? 0), thumbHeight))
  }

  private func thumb(
    _ which: Thumb, _ drawn: ResolvedRangeSlider, travel: CGFloat, size: CGSize
  ) -> some View {
    let value = which == .lower ? drawn.lower : drawn.upper
    let name = [drawn.accessibleName, which == .lower ? drawn.lowerName : drawn.upperName]
      .filter { !$0.isEmpty }.joined(separator: " ")
    return Color.clear
      .partBox(drawn.thumb, alignment: .center)
      .frame(width: size.width, height: size.height)
      .padding(.leading, travel * share(value, drawn))
      .overlay {
        if focusedThumb == which {
          Color.clear.frame(width: size.width, height: size.height)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .padding(.leading, travel * share(value, drawn))
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement()
      .accessibilityLabel(name)
      .accessibilityValue(spoken(value))
      .accessibilityAdjustableAction { adjust in
        switch adjust {
        case .increment: move(which, drawn, to: value + drawn.step)
        case .decrement: move(which, drawn, to: value - drawn.step)
        @unknown default: break
        }
      }
  }

  private func drag(
    _ drawn: ResolvedRangeSlider, travel: CGFloat, thumbWidth: CGFloat
  ) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { change in
        guard drawn.acceptsEdits else { return }
        focus.moved(to: slider.key.value)
        let held =
          dragged
          ?? nearestThumb(
            to: change.startLocation.x, drawn, travel: travel, thumbWidth: thumbWidth)
        dragged = held
        focusedThumb = held.thumb
        let across =
          direction == .rightToLeft ? -change.translation.width : change.translation.width
        let span = drawn.max - drawn.min
        move(held.thumb, drawn, to: held.start + Double(across / travel) * span)
      }
      .onEnded { _ in dragged = nil }
  }

  /// The thumb whose centre is nearest to `position` (from the left edge), with the number it holds.
  private func nearestThumb(
    to position: CGFloat, _ drawn: ResolvedRangeSlider, travel: CGFloat, thumbWidth: CGFloat
  ) -> (thumb: Thumb, start: Double) {
    let atStart = direction == .rightToLeft ? travel + thumbWidth - position : position
    let lowerCentre = thumbWidth / 2 + travel * share(drawn.lower, drawn)
    let toLower = abs(atStart - lowerCentre)
    let toUpper = abs(atStart - (thumbWidth / 2 + travel * share(drawn.upper, drawn)))
    // Side by side: the lower one at the end of the rail and for a press before them, else the upper one.
    let lowerIsNearer =
      toLower == toUpper ? drawn.lower >= drawn.max || atStart < lowerCentre : toLower < toUpper
    return lowerIsNearer ? (.lower, drawn.lower) : (.upper, drawn.upper)
  }

  /// Sends the new numbers when `to`, snapped to a step and kept between its bound and the other thumb, moves a thumb.
  private func move(_ which: Thumb, _ drawn: ResolvedRangeSlider, to target: Double) {
    guard drawn.acceptsEdits else { return }
    let snapped = ((target - drawn.min) / drawn.step).rounded() * drawn.step + drawn.min
    let lower = which == .lower ? min(max(snapped, drawn.min), drawn.upper) : drawn.lower
    let upper = which == .upper ? max(min(snapped, drawn.max), drawn.lower) : drawn.upper
    if lower != drawn.lower || upper != drawn.upper {
      inputs.send(.rangeChange(slider.key, lower: lower, upper: upper))
    }
  }

  private func share(_ value: Double, _ drawn: ResolvedRangeSlider) -> CGFloat {
    let span = drawn.max - drawn.min
    return span > 0 ? CGFloat((value - drawn.min) / span) : 0
  }

  /// A number as VoiceOver says it: `100`, not `100.0`.
  private func spoken(_ value: Double) -> String {
    if value == value.rounded(), let whole = Int(exactly: value) { return String(whole) }
    return String(value)
  }
}
