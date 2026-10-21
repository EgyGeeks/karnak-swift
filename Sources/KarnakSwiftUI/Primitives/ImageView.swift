import KarnakCore
import SwiftUI

/// `image`: the image loader's image in a box sized before loading, filled with the placeholder
/// color while loading and on failure (`docs/renderer-contract.md`, `image`). `contentScale`
/// `fit` letterboxes, `crop` covers and clips, and `fill` stretches. The box comes from the
/// node's layout and `aspectRatio` (``BoxContent/image(aspectRatio:)``), and the loader decodes
/// at its laid-out pixel size. A URL that isn't HTTPS draws only the placeholder. Images are
/// never mirrored in RTL.
///
/// The image is one accessibility element named by its semantics. A decorative image has
/// `semantics.hidden`, so it leaves the tree unless the engine kept it reachable.
struct ImageView: View {
  /// The image node.
  let image: ResolvedImage
  @Environment(\.karnakImageLoader) private var loader

  var body: some View {
    let placeholder = resolvedColor(image.placeholder)
    Group {
      if let url = httpsURL(image.url) {
        KarnakAsyncImage(
          url: url, loader: loader, placeholder: placeholder,
          contentMode: imageScaling(image.contentScale).contentMode)
      } else {
        placeholder
      }
    }
    .accessibilityElement(children: .ignore)
  }
}

/// `string` as a URL the loader accepts: absolute and HTTPS. Nil for anything else, which the
/// loader would refuse anyway.
func httpsURL(_ string: String) -> URL? {
  guard let url = URL(string: string), url.scheme?.lowercased() == "https", url.host != nil else {
    return nil
  }
  return url
}
