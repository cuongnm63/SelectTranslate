import Carbon

/// Phím tắt toàn hệ thống qua Carbon RegisterEventHotKey (không cần quyền đặc biệt).
final class HotKey {
    private static var nextID: UInt32 = 1

    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        id = Self.nextID
        Self.nextID += 1

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                // Mọi HotKey cùng nghe 1 loại event: chỉ xử lý đúng ID của mình, còn lại chuyển tiếp.
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
                )
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                guard status == noErr, pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
                hotKey.action()
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x5354_4C54), id: id) // "STLT"
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
