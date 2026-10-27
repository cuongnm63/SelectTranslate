import SwiftUI

/// Thay cho `@State`: với SDK macOS 27, `@State` là macro mà Command Line Tools không có
/// plugin (chỉ Xcode có) → build bằng CLT báo "plugin for module 'SwiftUIMacros' not found".
/// Bọc `State` trong một DynamicProperty thường nên SwiftUI vẫn quản lý trạng thái như cũ.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private let state: State<Value>

    init(wrappedValue: Value) {
        state = State(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { state.projectedValue }
}
