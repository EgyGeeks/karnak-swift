import Combine
import KarnakCore
import SwiftUI

/// What an input reports to its screen instance (`docs/renderer-contract.md`, Input events), addressed by the input
/// node's key. Fire-and-forget: the engine answers with trees and effects.
enum InputEvent {
  /// A `text_field`'s new text, or a `radio_group`'s or `select`'s picked option (`nil` clears the selection).
  case valueChange(NodeKey, String?)
  /// A `checkbox` or `switch` was toggled to this value.
  case checkedChange(NodeKey, Bool)
  /// A multiple `chip_group`'s or a `checkbox_group`'s selected option values, in the options' order.
  case selectionChange(NodeKey, [String])
  /// A `range_slider`'s lower and upper numbers.
  case rangeChange(NodeKey, lower: Double, upper: Double)
  /// Focus entered (`true`) or left (`false`) the input.
  case focusChange(NodeKey, Bool)
  /// The keyboard's action key was pressed on a `text_field`.
  case imeAction(NodeKey)
}

/// Where the inputs of the screen being drawn send their events: the root view's `onInput`. Inputs read it from the
/// environment, as clickable nodes read ``ActionSink``.
final class InputSink {
  /// The latest handler; the root view replaces it on every update.
  var handler: (InputEvent) -> Void

  /// Creates a sink that sends events to `handler`; the default drops them.
  init(handler: @escaping (InputEvent) -> Void = { _ in }) {
    self.handler = handler
  }

  /// Sends `event` to the screen instance.
  func send(_ event: InputEvent) {
    handler(event)
  }
}

/// The engine's `FocusRequest`s for one screen (`docs/renderer-contract.md`, Effects): the input whose key a request
/// names takes focus, which shows the keyboard for a text field. A request no input takes is dropped when the next tree
/// is shown, so a later input with that key never takes a stale one.
final class InputFocus {
  /// The key the latest request names, until an input takes it.
  private(set) var pending: String?
  /// Each request's key, as it comes; inputs drawn at the time hear it here.
  let requests = PassthroughSubject<String, Never>()
  /// The key of each input focus moves to, by a request or by the user, so every other input gives focus up: an
  /// input that can't take keyboard focus (a select, a radio group) still dismisses a text field's keyboard.
  let moves = PassthroughSubject<String, Never>()
  /// The key of the input focus moved to last, so an input can tell whether focus went elsewhere while it was
  /// sending an event (a `FocusRequest` the engine answered with at once).
  private(set) var latestMove: String?

  /// Asks the input with `key` to take focus.
  func request(_ key: String) {
    pending = key
    latestMove = key
    requests.send(key)
    moves.send(key)
  }

  /// Tells the other inputs that the input with `key` has focus now.
  func moved(to key: String) {
    latestMove = key
    moves.send(key)
  }

  /// Takes the waiting request if it names `key`: `true` once, for the input that takes focus.
  func take(_ key: String) -> Bool {
    guard pending == key else { return false }
    pending = nil
    return true
  }

  /// Drops a request no input took.
  func expire() {
    pending = nil
  }
}

extension EnvironmentValues {
  /// The sink for the input events of the screen being drawn; outside a screen they are dropped.
  @Entry var karnakInputs = InputSink()
  /// The focus requests of the screen being drawn; outside a screen there are none.
  @Entry var karnakInputFocus = InputFocus()
}

extension View {
  /// Gives `focused` to the input with `key` whenever the screen's ``InputFocus`` asks for it, including a request
  /// that came before the input appeared, takes it away when focus moves to another input, and tells the others
  /// when the input takes focus itself.
  func takesFocusRequests(
    _ key: String, focus: InputFocus, focused: FocusState<Bool>.Binding
  ) -> some View {
    onReceive(focus.requests) { requested in
      if requested == key, focus.take(key) { focused.wrappedValue = true }
    }
    .onReceive(focus.moves) { moved in
      if moved != key, focused.wrappedValue { focused.wrappedValue = false }
    }
    .onChange(of: focused.wrappedValue) { if $0 { focus.moved(to: key) } }
    .onAppear {
      if focus.take(key) { focused.wrappedValue = true }
    }
  }

  /// Sends `focusChange` for `key` each time `focused` flips.
  func reportsFocus(_ key: NodeKey, _ focused: Bool, to inputs: InputSink) -> some View {
    onChange(of: focused) { inputs.send(.focusChange(key, $0)) }
  }
}
