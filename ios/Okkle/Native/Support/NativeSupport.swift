import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision
enum OkkleColor {
  static let brand = Color(red: 0.03, green: 0.58, blue: 0.49)
  static let brandDark = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.44, green: 0.90, blue: 0.80, alpha: 1)
      : UIColor(red: 0.03, green: 0.36, blue: 0.31, alpha: 1)
  })
  static let mint = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.09, green: 0.24, blue: 0.21, alpha: 1)
      : UIColor(red: 0.83, green: 0.97, blue: 0.94, alpha: 1)
  })
  static let ink = Color(uiColor: .label)
  static let muted = Color(uiColor: .secondaryLabel)
  static let line = Color(uiColor: .separator)
  static let amber = Color(red: 0.86, green: 0.50, blue: 0.08)
  static let red = Color(red: 0.82, green: 0.20, blue: 0.18)
  static let blue = Color(red: 0.18, green: 0.39, blue: 0.86)
  static let fieldBackground = Color(uiColor: .secondarySystemBackground).opacity(0.82)
}

let gbpFormatter: NumberFormatter = {
  let formatter = NumberFormatter()
  formatter.numberStyle = .currency
  formatter.currencyCode = "GBP"
  formatter.maximumFractionDigits = 2
  formatter.minimumFractionDigits = 2
  return formatter
}()

let wholeGbpFormatter: NumberFormatter = {
  let formatter = NumberFormatter()
  formatter.numberStyle = .currency
  formatter.currencyCode = "GBP"
  formatter.maximumFractionDigits = 0
  formatter.minimumFractionDigits = 0
  return formatter
}()

func gbp(_ value: Double, whole: Bool = false) -> String {
  let formatter = whole ? wholeGbpFormatter : gbpFormatter
  return formatter.string(from: NSNumber(value: value)) ?? "GBP \(value)"
}

func headlineGbp(_ value: Double) -> String {
  abs(value) < 100 ? gbp(value) : gbp(value, whole: true)
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
