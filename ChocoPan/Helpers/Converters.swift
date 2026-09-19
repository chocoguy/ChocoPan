import Foundation

func FormatYear(year: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 0

    return formatter.string(from: NSNumber(value: year)) ?? ""
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

