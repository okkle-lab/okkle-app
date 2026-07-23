import PhotosUI
import SwiftUI
import UIKit
import Vision

struct NativeLogView: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var kind: NativeLogKind
  @State private var amount = ""
  @State private var distance = ""
  @State private var category = ""
  @State private var merchant = ""
  @State private var note = ""
  @State private var platform = "Uber Eats"
  @State private var vehicle: NativeVehicle = .car
  @State private var period: NativePayPeriod = .day
  @State private var date = Date()
  @State private var receiptItem: PhotosPickerItem?
  @State private var receiptImage: UIImage?
  @State private var receiptData: Data?
  @State private var receiptScanMessage = "Add a receipt and Okkle will try to fill the expense details."
  @State private var receiptScanning = false
  @State private var showCamera = false
  @State private var savedRecord: NativeRecord?
  @State private var showSavedNotice = false
  @State private var stepIndex = 0
  private let defaultKind: NativeLogKind
  private let allowedKinds: [NativeLogKind]
  private let screenTitle: String
  private let screenSubtitle: String
  private let onCloseAction: () -> Void
  private let onViewRecordsAction: () -> Void

  private enum LogStep: String {
    case kind
    case receipt
    case primary
    case details
    case date
    case review
  }

  private static func normalizedKinds(_ kinds: [NativeLogKind]) -> [NativeLogKind] {
    let orderedKinds = NativeLogKind.allCases.filter { kinds.contains($0) }
    return orderedKinds.isEmpty ? [.income] : orderedKinds
  }

  init(
    initialKind: NativeLogKind = .income,
    allowedKinds: [NativeLogKind] = NativeLogKind.allCases,
    title: String = "Log",
    subtitle: String = "Add one record at a time.",
    onClose: @escaping () -> Void,
    onViewRecords: @escaping () -> Void
  ) {
    let normalizedKinds = NativeLogView.normalizedKinds(allowedKinds)
    let startingKind = normalizedKinds.contains(initialKind) ? initialKind : normalizedKinds[0]
    _kind = State(initialValue: startingKind)
    self.defaultKind = startingKind
    self.allowedKinds = normalizedKinds
    self.screenTitle = title
    self.screenSubtitle = subtitle
    self.onCloseAction = onClose
    self.onViewRecordsAction = onViewRecords
  }

  var body: some View {
    ZStack {
      NativeScreen(
        title: screenTitle, collapsedTitle: screenTitle, subtitle: screenSubtitle,
        onClose: {
          resetEntry()
          onCloseAction()
        },
        showsProfileButton: false
      ) {
        VStack(alignment: .leading, spacing: 16) {
          stepProgress
          stepCard
          stepFooter
        }
      }

      if showSavedNotice, let savedRecord {
        savedNotice(for: savedRecord)
      }
    }
    .sheet(isPresented: $showCamera) {
      NativeCameraPicker(image: $receiptImage, imageData: $receiptData)
        .ignoresSafeArea()
    }
    .task(id: receiptItem) {
      guard let receiptItem, let data = try? await receiptItem.loadTransferable(type: Data.self) else { return }
      receiptData = data
      receiptImage = UIImage(data: data)
    }
    .onChange(of: receiptData) { data in
      guard let data else { return }
      scanReceipt(data)
    }
    .toolbar(showSavedNotice ? .hidden : .visible, for: .tabBar)
  }

  private var steps: [LogStep] {
    let entrySteps: [LogStep]
    switch kind {
    case .income:
      entrySteps = savedPlatformOptions.count == 1
        ? [.receipt, .primary, .date, .review]
        : [.receipt, .primary, .details, .date, .review]
    case .expense:
      entrySteps = [.receipt, .primary, .details, .date, .review]
    case .mileage:
      entrySteps = [.primary, .details, .date, .review]
    }
    return allowedKinds.count > 1 ? [.kind] + entrySteps : entrySteps
  }

  private var currentStep: LogStep {
    steps[min(stepIndex, steps.count - 1)]
  }

  private var progressValue: Double {
    Double(stepIndex + 1) / Double(steps.count)
  }

  private var stepProgress: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Step \(stepIndex + 1) of \(steps.count)")
          .font(.system(size: 13, weight: .heavy, design: .rounded))
          .foregroundStyle(OkkleColor.brandDark)
        Spacer()
        Text(kind.label)
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(OkkleColor.muted)
      }

      ProgressView(value: progressValue)
        .tint(OkkleColor.brand)
        .scaleEffect(x: 1, y: 1.2, anchor: .center)
    }
  }

  private var stepCard: some View {
    Group {
      if currentStep == .kind {
        stepCardContent
      } else {
        NativeGlassCard(cornerRadius: 30) {
          stepCardContent
        }
      }
    }
    .animation(.easeInOut(duration: 0.18), value: currentStep.rawValue)
  }

  private var stepCardContent: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 8) {
        Text(stepTitle)
          .font(.system(size: 30, weight: .heavy, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
          .fixedSize(horizontal: false, vertical: true)
        Text(stepSubtitle)
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }

      stepContent
    }
  }

  @ViewBuilder
  private var stepContent: some View {
    switch currentStep {
    case .kind:
      kindStep
    case .receipt:
      receiptStep
    case .primary:
      primaryStep
    case .details:
      detailsStep
    case .date:
      dateStep
    case .review:
      reviewStep
    }
  }

  private var kindStep: some View {
    VStack(spacing: 12) {
      ForEach(allowedKinds) { item in
        nativeChoiceRow(
          title: item.label,
          subtitle: kindDescription(for: item),
          symbol: item.symbol,
          selected: kind == item,
          tint: tint(for: item)
        ) {
          if kind != item {
            kind = item
            resetEntry(keepKind: true)
          }
        }
      }
    }
  }

  private var receiptStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      receiptBetaPanel
      Text(kind == .income ? "This is optional. Attach a payout screenshot if you want it stored with the record." : "This is optional. Okkle will try to read the receipt, but you can always enter details yourself.")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
    }
  }

  private var primaryStep: some View {
    VStack(alignment: .leading, spacing: 14) {
      if kind == .mileage {
        nativeNumberField(title: "Miles driven", text: $distance, placeholder: "0.0")
      } else {
        nativeNumberField(title: kind == .income ? "Earnings amount" : "Expense amount", text: $amount, placeholder: "0.00")
      }

      if !primaryValueCaption.isEmpty {
        Text(primaryValueCaption)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
      }
    }
  }

  @ViewBuilder
  private var detailsStep: some View {
    switch kind {
    case .income:
      NativeFreeTextDropdown(
        title: "Delivery service",
        placeholder: "Choose the delivery service",
        options: platformOptions,
        text: $platform
      )
    case .expense:
      VStack(spacing: 14) {
        NativeFreeTextDropdown(
          title: "Category *",
          placeholder: "Choose or type a category",
          options: categoryOptions,
          text: $category
        )
        Text("Required. Pick the closest expense type so this can be saved correctly.")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
          .frame(maxWidth: .infinity, alignment: .leading)
        nativeTextField(
          title: "Merchant (optional)",
          placeholder: merchantPlaceholder,
          text: $merchant
        )
        nativeTextEditor(
          title: "Note (optional)",
          placeholder: "e.g. Phone data for courier apps, parking while collecting orders",
          text: $note
        )
      }
    case .mileage:
      VStack(spacing: 12) {
        ForEach(NativeVehicle.allCases) { item in
          nativeChoiceRow(
            title: item.label,
            subtitle: mileageRateDescription(for: item),
            symbol: item.symbol,
            selected: vehicle == item,
            tint: OkkleColor.brand
          ) {
            vehicle = item
          }
        }
      }
    }
  }

  private var dateStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Picker("Period", selection: $period) {
        ForEach(NativePayPeriod.allCases) { Text($0.label).tag($0) }
      }
      .pickerStyle(.segmented)

      DatePicker(period == .week ? "Week ending" : "Date", selection: $date, displayedComponents: .date)
        .datePickerStyle(.compact)

      Text(dateCaption)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
    }
  }

  private var reviewStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(reviewRows, id: \.label) { row in
        HStack(alignment: .top, spacing: 12) {
          Text(row.label)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(OkkleColor.muted)
            .frame(width: 86, alignment: .leading)
          Text(row.value)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(OkkleColor.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(OkkleColor.fieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      }
    }
  }

  private var stepFooter: some View {
    HStack(spacing: 12) {
      Button {
        goBack()
      } label: {
        Label("Back", systemImage: "chevron.left")
          .font(.system(size: 16, weight: .bold))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
      }
      .buttonStyle(.bordered)
      .disabled(stepIndex == 0)

      Button {
        goForward()
      } label: {
        Label(primaryActionTitle, systemImage: currentStep == .review ? "checkmark.circle.fill" : "arrow.right")
          .font(.system(size: 16, weight: .bold))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
      }
      .buttonStyle(.borderedProminent)
      .tint(currentStep == .review ? .green : OkkleColor.brand)
      .disabled(!canContinue)
    }
  }

  private var canSave: Bool {
    switch kind {
    case .mileage:
      return Double(distance) ?? 0 > 0
    case .income:
      return Double(amount) ?? 0 > 0 && !incomePlatform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .expense:
      return (Double(amount) ?? 0 > 0)
        && !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  private var canContinue: Bool {
    switch currentStep {
    case .kind:
      return true
    case .receipt:
      return !receiptScanning
    case .primary:
      switch kind {
      case .mileage:
        return Double(distance) ?? 0 > 0
      case .income, .expense:
        return Double(amount) ?? 0 > 0
      }
    case .details:
      switch kind {
      case .income:
        return !platform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      case .expense:
        return !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      case .mileage:
        return true
      }
    case .date:
      return true
    case .review:
      return canSave
    }
  }

  private var primaryActionTitle: String {
    if currentStep == .review {
      return "Save entry"
    }
    if currentStep == .receipt && receiptData == nil {
      return "Skip receipt"
    }
    return "Continue"
  }

  private var stepTitle: String {
    switch currentStep {
    case .kind:
      return "What are you logging?"
    case .receipt:
      return kind == .income ? "Add a photo?" : "Add a receipt?"
    case .primary:
      return kind == .mileage ? "How many miles?" : "How much was it?"
    case .details:
      switch kind {
      case .income:
        return "Who paid you?"
      case .expense:
        return "What was it for?"
      case .mileage:
        return "Which vehicle?"
      }
    case .date:
      return "When was this?"
    case .review:
      return "Review and save"
    }
  }

  private var stepSubtitle: String {
    switch currentStep {
    case .kind:
      return "Choose the type of record you want to add."
    case .receipt:
      return "Attach a photo if it helps. You can skip this step."
    case .primary:
      return kind == .mileage ? "Enter the business miles for this record." : "Enter the exact amount before tax."
    case .details:
      switch kind {
      case .income:
        return "Pick a saved platform or type a new one."
      case .expense:
        return "Category is required. Merchant and note are optional context for the accountant pack."
      case .mileage:
        return "Okkle uses this to calculate the mileage deduction."
      }
    case .date:
      return "Choose whether this belongs to a day or a week."
    case .review:
      return "Check the details before adding this to Records."
    }
  }

  private var primaryValueCaption: String {
    switch kind {
    case .mileage:
      guard let milesValue = Double(distance), milesValue > 0 else { return "" }
      return "\(miles(milesValue)) will estimate \(gbp(store.calcDeduction(miles: milesValue, vehicle: vehicle, date: date))) deduction."
    case .income:
      guard let amountValue = Double(amount), amountValue > 0 else { return "" }
      return "\(gbp(amountValue)) earnings will be saved."
    case .expense:
      guard let amountValue = Double(amount), amountValue > 0 else { return "" }
      return "\(gbp(amountValue)) expense will be saved."
    }
  }

  private var dateCaption: String {
    let bounds = store.periodBounds(for: date, period: period)
    switch period {
    case .day:
      return "This will be recorded on \(shortDate(date))."
    case .week:
      return "This week covers \(shortDate(bounds.start)) to \(shortDate(bounds.end))."
    }
  }

  private var reviewRows: [(label: String, value: String)] {
    let bounds = store.periodBounds(for: date, period: period)
    var rows: [(String, String)] = [("Type", kind.label)]

    switch kind {
    case .mileage:
      let milesValue = Double(distance) ?? 0
      rows.append(("Miles", miles(milesValue)))
      rows.append(("Vehicle", vehicle.label))
      rows.append(("Deduction", gbp(store.calcDeduction(miles: milesValue, vehicle: vehicle, date: date))))
    case .income:
      rows.append(("Amount", gbp(Double(amount) ?? 0)))
      rows.append(("Platform", incomePlatform.trimmingCharacters(in: .whitespacesAndNewlines)))
    case .expense:
      rows.append(("Amount", gbp(Double(amount) ?? 0)))
      let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
      if !cleanCategory.isEmpty {
        rows.append(("Category", cleanCategory))
      }
      let cleanMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
      if !cleanMerchant.isEmpty {
        rows.append(("Merchant", cleanMerchant))
      }
      let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
      if !cleanNote.isEmpty {
        rows.append(("Note", cleanNote))
      }
    }

    rows.append(("Period", period.label))
    rows.append(("Date", period == .week ? "\(shortDate(bounds.start)) to \(shortDate(bounds.end))" : shortDate(date)))
    if kind != .mileage {
      rows.append(("Photo", receiptData == nil ? "Not attached" : "Attached"))
    }
    return rows
  }

  private var receiptPanelMessage: String {
    if kind == .income {
      return receiptData == nil
        ? "Attach a payout screenshot or other proof for your records."
        : "Photo attached and ready to save with this earning."
    }
    return receiptScanning ? "Scanning receipt..." : receiptScanMessage
  }

  private func goBack() {
    hideKeyboard()
    withAnimation(.easeInOut(duration: 0.18)) {
      stepIndex = max(0, stepIndex - 1)
    }
  }

  private func goForward() {
    hideKeyboard()
    guard canContinue else { return }

    if currentStep == .review {
      saveRecord()
      withAnimation(.easeInOut(duration: 0.18)) {
        showSavedNotice = true
      }
      return
    }

    withAnimation(.easeInOut(duration: 0.18)) {
      stepIndex = min(stepIndex + 1, steps.count - 1)
    }
  }

  private func nativeChoiceRow(
    title: String,
    subtitle: String,
    symbol: String,
    selected: Bool,
    tint: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 14) {
        Image(systemName: symbol)
          .font(.system(size: 20, weight: .bold))
          .foregroundStyle(selected ? tint : OkkleColor.muted)
          .frame(width: 46, height: 46)
          .background(selected ? tint.opacity(0.15) : OkkleColor.fieldBackground, in: Circle())

        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.system(size: 17, weight: .heavy))
            .foregroundStyle(OkkleColor.ink)
          Text(subtitle)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 8)

        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(selected ? tint : OkkleColor.muted.opacity(0.45))
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(selected ? tint.opacity(0.13) : OkkleColor.fieldBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private func savedNotice(for record: NativeRecord) -> some View {
    ZStack {
      Rectangle()
        .fill(.ultraThinMaterial)
        .ignoresSafeArea()

      Color.black.opacity(0.20)
        .ignoresSafeArea()
        .onTapGesture {}

      RadialGradient(
        colors: [
          .green.opacity(0.26),
          .green.opacity(0.08),
          .clear
        ],
        center: .center,
        startRadius: 40,
        endRadius: 310
      )
      .ignoresSafeArea()
      .allowsHitTesting(false)

      VStack(spacing: 26) {
        Spacer()

        VStack(spacing: 16) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 70, weight: .bold))
            .foregroundStyle(.green)
            .shadow(color: .green.opacity(0.34), radius: 28, y: 12)

          VStack(spacing: 8) {
            Text("Saved to Records")
              .font(.system(size: 32, weight: .heavy, design: .rounded))
              .foregroundStyle(.white)
            Text(savedSummary(for: record))
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(.white.opacity(0.78))
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .frame(maxWidth: 360)

        HStack(spacing: 12) {
          Button {
            resetEntry()
            onCloseAction()
          } label: {
            Text("Done")
              .font(.system(size: 16, weight: .bold))
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .controlSize(.large)
          .tint(.white)

          Button {
            resetEntry()
            onViewRecordsAction()
          } label: {
            Text("View records")
              .font(.system(size: 16, weight: .bold))
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .tint(.green)
        }
        .frame(maxWidth: 360)

        Spacer()
      }
      .padding(.horizontal, 28)
    }
    .transition(.opacity)
  }

  private func savedSummary(for record: NativeRecord) -> String {
    switch record.kind {
    case .mileage:
      return "\(miles(record.miles ?? 0)) saved with \(gbp(record.deduction ?? 0)) deduction."
    case .income:
      return "\(gbp(record.amount ?? 0)) earnings saved."
    case .expense:
      return "\(gbp(record.amount ?? 0)) expense saved."
    }
  }

  private func kindDescription(for kind: NativeLogKind) -> String {
    switch kind {
    case .income:
      return "Delivery pay, tips and bonuses."
    case .expense:
      return "Costs like fuel, parking and kit."
    case .mileage:
      return "Manual business miles for a trip."
    }
  }

  private func tint(for kind: NativeLogKind) -> Color {
    switch kind {
    case .income:
      return OkkleColor.brand
    case .expense:
      return OkkleColor.red
    case .mileage:
      return OkkleColor.blue
    }
  }

  private func mileageRateDescription(for vehicle: NativeVehicle) -> String {
    switch store.settings.taxCountry {
    case .uk:
      guard store.settings.expenseMethod == .simplified else {
        return "Actual costs claimed - no mileage rate applied."
      }
      let band = vehicle.rateBand(on: date)
      let first = Int((band.first * 100).rounded())
      let after = Int((band.after * 100).rounded())
      if first == after {
        return "\(first)p per business mile."
      }
      return "\(first)p first band, then \(after)p per mile."
    case .us:
      guard vehicle != .bike else {
        return "No IRS mileage rate for bicycles."
      }
      let cents = Int((USTaxCalculator.standardMileageRate(on: date) * 100).rounded())
      return "\(cents)c per business mile (IRS standard rate)."
    }
  }

  private var platformOptions: [String] {
    uniqueStrings(savedPlatformOptions + [platform])
  }

  private var incomePlatform: String {
    if savedPlatformOptions.count == 1 {
      return savedPlatformOptions[0]
    }
    return platform
  }

  private var merchantPlaceholder: String {
    switch store.settings.taxCountry {
    case .uk: return "e.g. Shell, Halfords, Vodafone"
    case .us: return "e.g. Shell, AutoZone, Verizon"
    }
  }

  private var categoryOptions: [String] {
    let recent = store.records
      .filter { $0.kind == .expense }
      .compactMap { $0.category }
    return uniqueStrings(recent + nativeExpenseCategories)
  }

  private var savedPlatformOptions: [String] {
    uniqueStrings(store.settings.platforms)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private var savedMessage: String {
    guard let savedRecord else { return "" }
    switch savedRecord.kind {
    case .mileage:
      return "\(miles(savedRecord.miles ?? 0)) saved with \(gbp(savedRecord.deduction ?? 0, whole: true)) deduction."
    case .income:
      return "\(gbp(savedRecord.amount ?? 0)) earnings saved."
    case .expense:
      return "\(gbp(savedRecord.amount ?? 0)) expense saved."
    }
  }

  private var receiptBetaPanel: some View {
    ZStack(alignment: .topTrailing) {
      VStack(alignment: .leading, spacing: 12) {
        Label(kind == .income ? "Photo attachment" : "Receipt scan", systemImage: kind == .income ? "photo" : "wand.and.stars")
          .font(.system(size: 15, weight: .heavy))
          .foregroundStyle(OkkleColor.brandDark)
          .padding(.trailing, 74)
        Text(receiptPanelMessage)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .padding(.trailing, 8)

        HStack(spacing: 10) {
          PhotosPicker(selection: $receiptItem, matching: .images) {
            Label("Choose photo", systemImage: "photo")
              .font(.system(size: 14, weight: .bold))
              .frame(maxWidth: .infinity, minHeight: 42)
          }
          .buttonStyle(.borderedProminent)
          .tint(OkkleColor.brand)

          Button {
            showCamera = true
          } label: {
            Label("Camera", systemImage: "camera")
              .font(.system(size: 14, weight: .bold))
              .frame(maxWidth: .infinity, minHeight: 42)
          }
          .buttonStyle(.borderedProminent)
          .tint(OkkleColor.brand)
        }

        if let receiptImage {
          Image(uiImage: receiptImage)
            .resizable()
            .scaledToFill()
            .frame(height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
      }

      Text("BETA")
        .font(.system(size: 11, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.purple, in: Capsule())
        .shadow(color: .purple.opacity(0.28), radius: 12, y: 6)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      LinearGradient(
        colors: [OkkleColor.mint.opacity(0.8), Color(uiColor: .secondarySystemBackground).opacity(0.82)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      ),
      in: RoundedRectangle(cornerRadius: 22, style: .continuous)
    )
  }

  private func scanReceipt(_ data: Data) {
    guard kind == .expense, let image = UIImage(data: data), let cgImage = image.cgImage else { return }
    receiptScanning = true
    receiptScanMessage = "Scanning receipt..."

    let request = VNRecognizeTextRequest { request, error in
      let observations = request.results as? [VNRecognizedTextObservation] ?? []
      let lines = observations.compactMap { $0.topCandidates(1).first?.string }
      let parsed = nativeParseReceipt(lines: lines)

      DispatchQueue.main.async {
        receiptScanning = false
        applyReceiptScan(parsed)
        if parsed.hasValues {
          receiptScanMessage = parsed.summary
        } else if let error {
          receiptScanMessage = "Could not scan this receipt. \(error.localizedDescription)"
        } else {
          receiptScanMessage = "Could not confidently read amount, category or merchant. You can still enter them manually."
        }
      }
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
      } catch {
        DispatchQueue.main.async {
          receiptScanning = false
          receiptScanMessage = "Could not scan this receipt. \(error.localizedDescription)"
        }
      }
    }
  }

  private func applyReceiptScan(_ result: NativeReceiptScanResult) {
    if amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let parsedAmount = result.amount {
      amount = String(format: "%.2f", parsedAmount)
    }
    if category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let parsedCategory = result.category {
      category = parsedCategory
    }
    if merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let parsedMerchant = result.merchant {
      merchant = parsedMerchant
    }
  }

  private func nativeNumberField(title: String, text: Binding<String>, placeholder: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(OkkleColor.ink)
      NativeNumberDoneTextField(text: text, placeholder: placeholder, fontSize: 30, fontWeight: .bold)
        .frame(height: 48)
        .padding(14)
        .background(OkkleColor.fieldBackground, in: RoundedRectangle(cornerRadius: 18))
    }
  }

  private func nativeTextField(title: String, placeholder: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(OkkleColor.ink)
      TextField(placeholder, text: text)
        .font(.system(size: 16, weight: .semibold))
        .textInputAutocapitalization(.words)
        .padding(14)
        .background(OkkleColor.fieldBackground, in: RoundedRectangle(cornerRadius: 18))
    }
  }

  private func nativeTextEditor(title: String, placeholder: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(OkkleColor.ink)
      ZStack(alignment: .topLeading) {
        if text.wrappedValue.isEmpty {
          Text(placeholder)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(OkkleColor.muted.opacity(0.72))
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .allowsHitTesting(false)
        }
        TextEditor(text: text)
          .font(.system(size: 15, weight: .semibold))
          .scrollContentBackground(.hidden)
          .padding(10)
          .frame(minHeight: 96)
      }
      .background(OkkleColor.fieldBackground, in: RoundedRectangle(cornerRadius: 18))
    }
  }

  private func saveRecord() {
    let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanPlatform = incomePlatform.trimmingCharacters(in: .whitespacesAndNewlines)
    let receiptPayload = nativeOptimizedReceiptData(image: receiptImage, data: receiptData)
    let bounds = store.periodBounds(for: date, period: period)
    let record: NativeRecord
    switch kind {
    case .mileage:
      let milesValue = Double(distance) ?? 0
      record = NativeRecord(
        kind: .mileage,
        platform: nil,
        vehicle: vehicle,
        amount: nil,
        miles: milesValue,
        deduction: store.calcDeduction(miles: milesValue, vehicle: vehicle, date: date),
        category: nil,
        merchant: nil,
        note: nil,
        date: date,
        period: period,
        periodStart: bounds.start,
        periodEnd: bounds.end,
        receiptImageData: nil
      )
    case .income:
      record = NativeRecord(
        kind: .income,
        platform: cleanPlatform,
        vehicle: nil,
        amount: Double(amount) ?? 0,
        miles: nil,
        deduction: nil,
        category: nil,
        merchant: nil,
        note: nil,
        date: date,
        period: period,
        periodStart: bounds.start,
        periodEnd: bounds.end,
        receiptImageData: receiptPayload
      )
      store.settings.platforms = uniqueStrings(store.settings.platforms + [cleanPlatform])
    case .expense:
      record = NativeRecord(
        kind: .expense,
        platform: nil,
        vehicle: nil,
        amount: Double(amount) ?? 0,
        miles: nil,
        deduction: nil,
        category: cleanCategory.isEmpty ? nil : cleanCategory,
        merchant: cleanMerchant.isEmpty ? nil : cleanMerchant,
        note: cleanNote.isEmpty ? nil : cleanNote,
        date: date,
        period: period,
        periodStart: bounds.start,
        periodEnd: bounds.end,
        receiptImageData: receiptPayload
      )
    }
    store.addRecord(record)
    savedRecord = record
  }

  private func resetEntry(keepKind: Bool = false) {
    if !keepKind { kind = defaultKind }
    amount = ""
    distance = ""
    category = ""
    merchant = ""
    note = ""
    vehicle = store.settings.defaultVehicle
    platform = savedPlatformOptions.first ?? "Uber Eats"
    period = .day
    date = Date()
    receiptImage = nil
    receiptData = nil
    receiptItem = nil
    receiptScanMessage = "Add a receipt and Okkle will try to fill the expense details."
    receiptScanning = false
    savedRecord = nil
    showSavedNotice = false
    stepIndex = 0
  }
}
