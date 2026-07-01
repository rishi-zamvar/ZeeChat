import SwiftUI
import UIKit

private struct DismissKeyboardOnTapOutside: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
            )
    }
}

extension View {
    func dismissKeyboardOnTapOutside() -> some View {
        modifier(DismissKeyboardOnTapOutside())
    }
}
