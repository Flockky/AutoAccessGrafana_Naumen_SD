# Grafana Access Grant Script 🚀

Этот PowerShell скрипт автоматизирует добавление пользователей в команды Grafana через API.  
Он поддерживает создание пользователя, если его ещё нет, и отправку email-уведомлений в случае ошибок.  

---

## ⚙️ Предназначение

Скрипт выполняет следующие шаги:

1. Игнорирует SSL ошибки (удобно для тестовых контуров с самоподписанными сертификатами).  
2. Проверяет, существует ли пользователь в Grafana; если нет — создаёт его.  
3. Находит команду по имени.  
4. Проверяет членство пользователя в команде.  
5. Если пользователь ещё не в команде — добавляет его.  
6. В случае ошибки отправляет email уведомление на адрес запроса.

---

## 📝 Параметры скрипта

Скрипт принимает параметры через блок `param()`.  
Если вы запускаете через **Groovy обёртку**, туда можно передавать значения из SD.

```powershell
param (
    [string]$Arg_Username      = "ivanov.ii",                  # Логин пользователя в Grafana
    [string]$Arg_FIO           = "Ivan Ivanov",               # ФИО пользователя
    [string]$Arg_Email         = "ivanov.ii@sberins.ru",      # Email пользователя
    [string]$Arg_TeamName      = "Administrators Grafana",    # Имя команды Grafana
    [string]$Arg_Contour       = "Pre-Production Grafana",    # Контур Grafana (Pre-Production или Production)
    [string]$Arg_RequesterEmail = "Email_for_error_alert"     # Email того, кто запросил действие (для уведомлений об ошибках)
)
```

> ⚠️ В скрипте нужно **заменить заглушки** на ваши реальные параметры или на передачу из SD/Groovy.  

---

## 🔧 Конфигурация скрипта

В скрипте есть блок конфигурации:

```powershell
$DEFAULT_PASSWORD    = "Qq123456."           # Пароль для нового пользователя
$ADMIN_LOGIN         = "Grafana Admin Login" # Логин администратора Grafana
$ADMIN_PASSWORD      = "Grafana Admin Password" # Пароль администратора Grafana

# Контуры Grafana: Имя -> URL
$Config = @{
    "Pre-Production Grafana" = "https://pregrafana.ru"
    "Production Grafana"     = "https://grafana.ru"
}
```

### Что нужно заменить

- `$ADMIN_LOGIN` и `$ADMIN_PASSWORD` → ваши учётные данные администратора Grafana.  
- `$DEFAULT_PASSWORD` → временный пароль для новых пользователей.  
- `$Config` → список контуров Grafana, которые вы используете.  

---

## ✉️ Настройка email уведомлений

Функция `Send-EmailAlert` отправляет email в случае ошибок.  

Параметры SMTP, которые нужно заполнить:

```powershell
$SmtpServer = "SmtpServer"
$SmtpPort = 587
$FromAddress = "SmtpServer_Address"
$Username = "SmtpServer_Username"
$Password = "SmtpServer_Password"
```

> ⚠️ Замените все заглушки на ваши реальные данные SMTP сервера.

---

## 🛠 Основные функции скрипта

1. `Set-SslTrust` — игнорирует ошибки SSL (удобно для тестовых окружений).  
2. `Invoke-GrafanaApi` — универсальная функция запроса к Grafana API.  
   - Автоматически использует Basic Auth с админскими логином/паролем.  
   - Возвращает статус, данные и ошибки.  
3. Основной блок:  
   - Поиск пользователя → создание при отсутствии  
   - Поиск команды  
   - Проверка членства  
   - Добавление пользователя  
   - Email уведомление при ошибке

---

## 📌 Как использовать

### 1. Локально через PowerShell:

```powershell
.\GrafanaAccessGrant.ps1 `
    -Arg_Username "ivanov.ii" `
    -Arg_FIO "Ivan Ivanov" `
    -Arg_Email "ivanov.ii@sberins.ru" `
    -Arg_TeamName "Administrators Grafana" `
    -Arg_Contour "Pre-Production Grafana" `
    -Arg_RequesterEmail "requester@sberins.ru"
```

### 2. Через Groovy обёртку из ServiceDesk

Передавать параметры из SD в скрипт можно так:

```groovy
powershell(
    script: "GrafanaAccessGrant.ps1",
    parameters: [
        Arg_Username: sdUsername,
        Arg_FIO: sdFIO,
        Arg_Email: sdEmail,
        Arg_TeamName: sdTeamName,
        Arg_Contour: sdContour,
        Arg_RequesterEmail: sdRequesterEmail
    ]
)
```

---

## ✅ Переменные, которые нужно заполнить

| Переменная | Назначение |
|------------|------------|
| `$Arg_Username` | Логин пользователя Grafana |
| `$Arg_FIO` | ФИО пользователя |
| `$Arg_Email` | Email пользователя |
| `$Arg_TeamName` | Название команды Grafana |
| `$Arg_Contour` | Контур Grafana (ключ из `$Config`) |
| `$Arg_RequesterEmail` | Email для уведомлений об ошибках |
| `$ADMIN_LOGIN` | Логин администратора Grafana |
| `$ADMIN_PASSWORD` | Пароль администратора Grafana |
| `$DEFAULT_PASSWORD` | Пароль для новых пользователей |
| SMTP параметры | `$SmtpServer`, `$FromAddress`, `$Username`, `$Password` |

---

## ⚠️ Важно

- Скрипт не проверяет сложность пароля для новых пользователей.  

---

## 🟢 Логика выполнения

```text
Start → Set SSL Trust → Check Contour → Find User → Create if missing
     → Find Team → Check Membership → Add if needed → Send Email on Error → Exit
```
