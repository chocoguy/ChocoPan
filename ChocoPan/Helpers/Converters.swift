import Foundation

func FormatYear(year: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 0

    return formatter.string(from: NSNumber(value: year)) ?? ""
}

/// Runtime as `mm:ss`, or `h:mm:ss` once it passes an hour.
func FormatDuration(seconds: Double) -> String {
    guard seconds > 0 else { return "" }
    let total = Int(seconds.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, total % 60)
    }
    return String(format: "%d:%02d", minutes, total % 60)
}

func FormatDate(date: Date?, notParsedString: String) -> String {
    if date == nil{
        return notParsedString
    }else{
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter.string(from: date!)
    }
}

func DateFromString(dateString: String) -> Date {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    
    if let date = dateFormatter.date(from: dateString) {
        return date
    } else {
        print("Error: Unable to convert string to date.")
        return Date()
    }
}

