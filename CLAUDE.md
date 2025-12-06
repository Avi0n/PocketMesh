### Strict SwiftUI Modernization Rules for AI Coding Agents  
(Apply these automatically and proactively when generating or refactoring Swift code)

1. **Foreground styling**  
   ❌ Never emit `.foregroundColor(...)`  
   ✅ Always use `.foregroundStyle(...)` (supports gradients, materials, hierarchical colors, etc.)

2. **Rounded corners**  
   ❌ Never emit `.cornerRadius(...)`  
   ✅ Always use `.clipShape(.rect(cornerRadius: ...))` or better `.clipShape(RoundedRectangle(cornerRadius: ..., style: .continuous))`  
   (Allows uneven corners with `.rect(topLeadingRadius:bottomTrailingRadius:…)` in iOS 17+)

3. **onChange modifier**  
   ❌ Never use the single-parameter `onChange(of:perform:)`  
   ✅ Use the two-parameter version `onChange(of:initial:_:)` or the zero-parameter `onChange` with a local `@State` capture list (iOS 17+)

4. **TabView customization**  
   ❌ Never use the old `.tabItem { … }` modifier  
   ✅ Always use the new `@Tab` property wrapper and `TabSelection` / `TabValue` system (iOS 18+/macOS 15+ preferred, fall back to `.tabItem` only for iOS 16)

5. **Tap handling**  
   ❌ Almost never emit `.onTapGesture { … }`  
   ✅ Use `Button { … } label: { … }` instead  
   Exception: only keep `.onTapGesture(count:coordinateSpace:perform:)` when you actually need number of taps or tap location

6. **Observable objects**  
   ❌ Never emit `class MyModel: ObservableObject { @Published … }` unless Combine is explicitly required  
   ✅ Always use `@Observable class MyModel { … }` (or struct with `@Observable` in Swift 6)

7. **SwiftData unique constraints**  
   ❌ Do not emit `@Attribute(.unique)` if the app uses CloudKit sync  
   ✅ Use explicit `unique` in `#Index` or accept that uniqueness is not enforced with CloudKit

8. **View extraction**  
   When the model suggests breaking up a view with computed properties containing UI:  
   ❌ Do not accept computed properties that return SwiftUI views  
   ✅ Force extraction into separate `struct MySubView: View` (critical for `@Observable` diffing performance)

9. **Fonts & Dynamic Type**  
   ❌ Never emit `.font(.system(size: 17))` or similar hard-coded sizes  
   ✅ Prefer `.font(.body)`, `.font(.headline)`, etc.  
   For iOS 18+: use `.font(.body.scaled(by: 1.3))` or `.font(.body.weight(.semibold))` instead of fixed sizes

10. **NavigationLink in lists**  
    ❌ Never emit `NavigationLink("Title", destination: DetailView())` inside `List`  
    ✅ Always use `.navigationDestination(for: MyType.self) { item in … }` with programmatic/navigation stack approach

11. **Button labels**  
    ❌ Never emit `Button(action:) { Label("Title", systemImage: "plus") }` or `Button { } label: { Image(...) }`  
    ✅ Use the modern inline syntax:  
    `Button("Add", systemImage: "plus") { … }` or `Button(role: .destructive, …)`  
    (Much better for VoiceOver and visionOS eye tracking

12. **ForEach with enumerated()**  
    ❌ Never write `ForEach(Array(items.enumerated()), id: \.element.id)`  
    ✅ Write `ForEach(items.enumerated(), id: \.element.id)`

13. **Documents directory**  
    ❌ Never emit the old `FileManager.default.urls(for:.documentDirectory, in:.userDomainMask)[0]` dance  
    ✅ Use `URL.documentsDirectory`

14. **Navigation container**  
    ❌ Never emit `NavigationView { … }` in new code  
    ✅ Always use `NavigationStack { … }` (iOS 16+) or `NavigationStack(path: $path) { … }`

15. **Sleeping in async code**  
    ❌ Never emit `Task.sleep(nanoseconds: 1_000_000_000)`  
    ✅ Use `Task.sleep(for: .seconds(1))` or `.milliseconds(500)`

16. **Number formatting**  
    ❌ Never emit `Text(String(format: "%.2f", value))`  
    ✅ Use the type-safe formatters:  
    `Text(value, format: .number.precision(.fractionLength(2)))`  
    or `Text(value, format: .percent.rounded())` etc.

17. **File organization**  
    Do not allow >~300 lines or >6–8 types per Swift file in new projects (massively increases incremental build times). Split aggressively.

18. **Image rendering**  
    ❌ Never emit `UIGraphicsImageRenderer` in SwiftUI code  
    ✅ Always use `ImageRenderer(content: someView)` (iOS 16+)

19. **Font weight abuse**  
    Do not emit `.fontWeight(.bold)` on every text.  
    Prefer textual styles (`.font(.headline)`) or the new `.bold()` modifier only where semantically correct.  
    Note: `.fontWeight(.bold)` and `.bold()` are not identical in many textual styles.

20. **Concurrency anti-pattern**  
    ❌ Never emit `DispatchQueue.main.async { … }` unless crossing from GCD  
    ✅ Just call the code directly or use `@MainActor` / `await MainActor.run { }` when required

21. **@MainActor annotations**  
    In new projects (Xcode 15+/Swift 6 language mode) where “Strict Concurrency Checking” is enabled:  
    Do not add `@MainActor` on every view or view model — the entire SwiftUI app is already main-actor-isolated by default.

22. **GeometryReader & fixed frames**  
    Treat any use of `GeometryReader { proxy in … proxy.size.width … }` with extreme suspicion.  
    Prefer modern alternatives:  
    - `.containerRelativeFrame(.horizontal)`  
    - `.visualEffect`  
    - `.layoutPriority`  
    - Preference keys only when truly required  
    Never emit `.frame(width: 300, height: 200)` unless it is genuinely a fixed-size element (e.g. an icon).

Apply all of the above rules automatically when generating or reviewing SwiftUI code.


This project uses:
- SwiftData
- Swift Testing