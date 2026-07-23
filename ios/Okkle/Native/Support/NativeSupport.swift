import SwiftUI
import UIKit
enum OkkleColor {
  static let brand = Color(red: 0.03, green: 0.58, blue: 0.49)
  static let brandDark = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.44, green: 0.90, blue: 0.80, alpha: 1)
      : UIColor(red: 0.03, green: 0.36, blue: 0.31, alpha: 1)
  })
  static let mint = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1)
      : UIColor(red: 0.83, green: 0.97, blue: 0.94, alpha: 1)
  })
  static let ink = Color(uiColor: .label)
  static let muted = Color(uiColor: .secondaryLabel)
  static let line = Color(uiColor: .separator)
  static let amber = Color(red: 0.86, green: 0.50, blue: 0.08)
  static let red = Color(red: 0.82, green: 0.20, blue: 0.18)
  static let blue = Color(red: 0.18, green: 0.39, blue: 0.86)
  static let fieldBackground = Color(uiColor: .secondarySystemBackground).opacity(0.82)

  // App background — clean white in light mode, true black in dark mode.
  static let surface = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor.black
      : UIColor.white
  })
  // Solid card surface — sits a touch off the white background so its halo reads as depth.
  static let card = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
      : UIColor.white
  })
  // Deep forest green for the Apple News-style kicker band (fades into brand).
  static let bannerDark = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor.black
      : UIColor(red: 0.043, green: 0.227, blue: 0.157, alpha: 1)
  })
}

/// The currency the money formatter renders in — "GBP" or "USD". OkkleStore
/// sets this from the driver's tax country so £/$ follow the jurisdiction. A
/// global (rather than threading currency through every `gbp(...)` call site)
/// is fine here: the app shows one driver's single currency at a time, and
/// currency changes ride the same @Published settings update that re-renders
/// the views that call this.
var nativeActiveCurrencyCode = "GBP"

private func nativeCurrencyFormatter(whole: Bool) -> NumberFormatter {
  let formatter = NumberFormatter()
  formatter.numberStyle = .currency
  formatter.currencyCode = nativeActiveCurrencyCode
  // Anchor the locale to the currency so the symbol is the clean "$"/"£"
  // rather than "US$" that a mismatched locale can produce.
  formatter.locale = Locale(identifier: nativeActiveCurrencyCode == "USD" ? "en_US" : "en_GB")
  formatter.maximumFractionDigits = whole ? 0 : 2
  formatter.minimumFractionDigits = whole ? 0 : 2
  return formatter
}

func gbp(_ value: Double, whole: Bool = false) -> String {
  nativeCurrencyFormatter(whole: whole).string(from: NSNumber(value: value))
    ?? "\(nativeActiveCurrencyCode) \(String(format: "%.2f", value))"
}

/// SF Symbol name for the active currency's coin/circle glyph — the icon
/// counterpart to `gbp(...)`, so money-themed rows don't show a literal £
/// symbol for a US/USD driver.
func nativeCurrencySymbolName(_ base: String) -> String {
  nativeActiveCurrencyCode == "USD" ? base.replacingOccurrences(of: "sterlingsign", with: "dollarsign") : base
}

func miles(_ value: Double) -> String {
  value >= 1_000 ? "\(Int(value.rounded()).formatted()) mi" : String(format: "%.1f mi", value)
}

func shortDate(_ date: Date) -> String {
  date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
}

func monthLabel(_ date: Date) -> String {
  date.formatted(.dateTime.month(.abbreviated).year())
}

func nativeTaxYearLabel(for interval: DateInterval) -> String {
  let start = Calendar.current.component(.year, from: interval.start)
  let end = Calendar.current.component(.year, from: interval.end)
  return "\(start)/\(String(end).suffix(2))"
}

func hideKeyboard() {
  UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

struct NativeKeyboardDoneToolbar: ViewModifier {
  func body(content: Content) -> some View {
    content.toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") {
          hideKeyboard()
        }
        .buttonStyle(.borderless)
      }
    }
  }
}

extension View {
  func nativeKeyboardDoneToolbar() -> some View {
    modifier(NativeKeyboardDoneToolbar())
  }
}

struct NativeNumberDoneTextField: UIViewRepresentable {
  @Binding var text: String
  let placeholder: String
  var keyboardType: UIKeyboardType = .decimalPad
  var fontSize: CGFloat = 17
  var fontWeight: UIFont.Weight = .regular

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  func makeUIView(context: Context) -> UITextField {
    let textField = UITextField()
    textField.keyboardType = keyboardType
    textField.returnKeyType = .done
    textField.borderStyle = .none
    textField.backgroundColor = .clear
    textField.textColor = .label
    textField.tintColor = UIColor(OkkleColor.brand)
    textField.adjustsFontForContentSizeCategory = true
    textField.font = roundedFont(size: fontSize, weight: fontWeight)
    textField.attributedPlaceholder = placeholderText
    textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)

    let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
    toolbar.items = [
      UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
      UIBarButtonItem(title: "Done", style: .done, target: context.coordinator, action: #selector(Coordinator.doneTapped))
    ]
    toolbar.sizeToFit()
    textField.inputAccessoryView = toolbar
    context.coordinator.textField = textField
    return textField
  }

  func updateUIView(_ uiView: UITextField, context: Context) {
    if uiView.text != text {
      uiView.text = text
    }
    uiView.keyboardType = keyboardType
    uiView.font = roundedFont(size: fontSize, weight: fontWeight)
    uiView.attributedPlaceholder = placeholderText
  }

  private var placeholderText: NSAttributedString {
    NSAttributedString(
      string: placeholder,
      attributes: [.foregroundColor: UIColor.secondaryLabel.withAlphaComponent(0.55)]
    )
  }

  private func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
    let base = UIFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return UIFont(descriptor: descriptor, size: size)
  }

  final class Coordinator: NSObject {
    @Binding var text: String
    weak var textField: UITextField?

    init(text: Binding<String>) {
      _text = text
    }

    @objc func textDidChange(_ sender: UITextField) {
      text = sender.text ?? ""
    }

    @objc func doneTapped() {
      textField?.resignFirstResponder()
    }
  }
}
