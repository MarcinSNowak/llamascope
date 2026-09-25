import Foundation

/// Numer wydania dla tego, co nie ma `Info.plist`.
///
/// Aplikacja czyta wersję z pakietu i tak ma zostać — pakiet jest tym, co
/// dostaje użytkownik. Ale sonda z wiersza poleceń pakietu nie ma, a wypisuje
/// tę samą linię co log aplikacji i tę samą paczkę diagnostyczną (§10).
/// Wersja wpisana tam osobno była przez trzy szczeble nieprawdziwa: sonda
/// w repozytorium wydania 0.9.1 twierdziła, że jest wersją 0.5-rozwojową.
///
/// To jest dokładnie liczba w spokojnym kształcie, która nie opisuje niczego
/// — więc tu stoi jedna kopia, a `wydanie.sh` sprawdza przed budową, że
/// zgadza się z `MARKETING_VERSION` w `project.yml`. Numer, który nie ma jak
/// się rozjechać, jest tańszy niż numer, który trzeba pamiętać.
public enum LlamaScopeVersion {
    public static let current = "0.9.1"
}
