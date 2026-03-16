param (
    [string]$Arg_Username      = "ivanov.ii", # Заменить на передачу параметра
    [string]$Arg_FIO           = "Ivan Ivanov", # Заменить на передачу параметра
    [string]$Arg_Email         = "ivanov.ii@sberins.ru", # Заменить на передачу параметра
    [string]$Arg_TeamName      = "Administrators Grafana", # Заменить на передачу параметра
    [string]$Arg_Contour       = "Pre-Production Grafana", # Заменить на передачу параметра
    [string]$Arg_RequesterEmail = "Email_for_error_aleft" 
)

# ======= КОНФИГУРАЦИЯ =======
$DEFAULT_PASSWORD    = "Qq123456."
$ADMIN_LOGIN         = "Grafana Admin Login"
$ADMIN_PASSWORD      = "Grafana Admin Password"

# Словарь контуров: Имя -> URL
$Config = @{
    "Pre-Production Grafana" = "https://pregrafana.ru"
    "Production Grafana"     = "https://grafana.ru"
}

# ======= Функция отправки email =======
function Send-EmailAlert {
    param(
        [string]$ToAddress,
        [string]$Subject,
        [string]$Body
    )
    
    try {
        $SmtpServer = "SmtpServer"
        $SmtpPort = 587
        $FromAddress = "SmtpServer_Address"
        $Username = "SmtpServer_Username"
        $Password = "SmtpServer_Password"
        
        $SmtpClient = New-Object System.Net.Mail.SmtpClient($SmtpServer, $SmtpPort)
        $SmtpClient.EnableSsl = $true
        $SmtpClient.Credentials = New-Object System.Net.NetworkCredential($Username, $Password)
        
        $MailMessage = New-Object System.Net.Mail.MailMessage
        $MailMessage.From = $FromAddress
        $MailMessage.To.Add($ToAddress)
        $MailMessage.Subject = $Subject
        $MailMessage.Body = $Body
        $MailMessage.IsBodyHtml = $false
        
        $SmtpClient.Send($MailMessage)
        Write-Host "📧 Email alert sent successfully to: $ToAddress" -ForegroundColor Yellow
    }
    catch {
        Write-Host "❌ ERROR: Failed to send email alert: $_" -ForegroundColor Red
    }
    finally {
        if ($SmtpClient) { $SmtpClient.Dispose() }
        if ($MailMessage) { $MailMessage.Dispose() }
    }
}

# ======= Игнорирование SSL ошибок =======
function Set-SslTrust {
    if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
        Add-Type @"
using System.Net; using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) { return true; }
}
"@
    }
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

# ======= Универсальная функция запроса к Grafana API =======
function Invoke-GrafanaApi {
    param (
        [string]$Method,
        [string]$Uri,
        $Body = $null
    )
    
    $pair = "${ADMIN_LOGIN}:${ADMIN_PASSWORD}"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)
    
    $headers = @{ 
        "Authorization" = "Basic $base64"
        "Content-Type"  = "application/json"
        "Accept"        = "application/json"
    }
    
    $params = @{
        Uri         = "$GRAFANA_URL$Uri"
        Method      = $Method
        Headers     = $headers
        TimeoutSec  = 10
        UseBasicParsing = $true
    }
    
    if ($Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 10 -Compress:$false)
    }
    
    try {
        $resp = Invoke-WebRequest @params
        return @{
            Status = $resp.StatusCode
            Raw    = $resp.Content
            Data   = if ($resp.Content) { $resp.Content | ConvertFrom-Json -ErrorAction SilentlyContinue } else { $null }
        }
    }
    catch {
        if ($_.Exception.Response) {
            $errCode = $_.Exception.Response.StatusCode.value__
            $errStream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errStream)
            $reader.BaseStream.Position = 0
            $reader.DiscardBufferedData()
            $errBody = $reader.ReadToEnd()
            
            return @{
                Status = $errCode
                Error  = $errBody
                Raw    = $errBody
                Data   = ($errBody | ConvertFrom-Json -ErrorAction SilentlyContinue)
            }
        } else {
            throw $_
        }
    }
}

# ======= Основной блок =======
$ErrorActionPreference = "Stop"
$Success = $false
$errorMessage = ""

try {
    Write-Host "=== Запуск скрипта Grafana Access Grant ==="
    Set-SslTrust
    
    # Проверка контура
    if (-not $Config.ContainsKey($Arg_Contour)) {
        throw "Неверный контур: '$Arg_Contour'. Доступные варианты: $($Config.Keys -join ', ')"
    }
    
    $GRAFANA_URL = $Config[$Arg_Contour].Trim()
    Write-Host "Контур: $($Arg_Contour)"
    Write-Host "URL: $GRAFANA_URL"
    Write-Host "Цель: Пользователь '$Arg_Username' ($Arg_FIO), Команда '$Arg_TeamName'"
    
    # --- ШАГ 1: Поиск пользователя ---
    Write-Host "🔍 Поиск пользователя '$Arg_Username'..."
    $EncodedLogin = [System.Web.HttpUtility]::UrlEncode($Arg_Username)
    $LookupRes = Invoke-GrafanaApi -Method "GET" -Uri "/api/users/lookup?loginOrEmail=$EncodedLogin"
    
    $UserId = $null
    $UserExists = $false

    if ($LookupRes.Status -eq 200 -and $LookupRes.Data) {
        $UserExists = $true
        $UserId = $LookupRes.Data.id
        Write-Host "✅ Пользователь найден (ID: $UserId)" -ForegroundColor Green
    }
    elseif ($LookupRes.Status -eq 404) {
        Write-Host "⚠️ Пользователь не найден. Будет создан." -ForegroundColor Yellow
        $CreateBody = @{
            name     = $Arg_FIO
            email    = $Arg_Email
            login    = $Arg_Username
            password = $DEFAULT_PASSWORD
            OrgId    = 1
        }
        $CreateRes = Invoke-GrafanaApi -Method "POST" -Uri "/api/admin/users" -Body $CreateBody
        if ($CreateRes.Status -eq 200 -and $CreateRes.Data) {
            $UserId = $CreateRes.Data.id
            Write-Host "✅ Пользователь создан (ID: $UserId)" -ForegroundColor Green
            $UserExists = $true
        } else {
            throw "Ошибка создания: $($CreateRes.Raw)"
        }
    }
    else {
        throw "Ошибка при поиске пользователя: $($LookupRes.Raw)"
    }

    # --- ШАГ 2: Поиск команды ПО ИМЕНИ ---
    Write-Host "🔍 Поиск команды '$Arg_TeamName'..."
    $EncodedTeamName = [System.Web.HttpUtility]::UrlEncode($Arg_TeamName)
    $SearchRes = Invoke-GrafanaApi -Method "GET" -Uri "/api/teams/search?name=$EncodedTeamName"
    
    if ($SearchRes.Status -ne 200) {
        throw "Не удалось найти команду. Статус: $($SearchRes.Status). Ответ: $($SearchRes.Raw)"
    }

    $TeamsList = $SearchRes.Data.teams
    
    if (-not $TeamsList -or $TeamsList.Count -eq 0) {
        throw "Команда '$Arg_TeamName' не найдена в системе."
    }

    $FoundTeam = $TeamsList[0]
    $TeamId = $FoundTeam.id
    
    Write-Host "✅ Команда найдена: '$($FoundTeam.name)' (ID: $TeamId)" -ForegroundColor Green

    # --- ШАГ 3: Проверка членства и добавление ---
    Write-Host "🔍 Проверка членства пользователя (ID: $UserId) в команде..."
    $MembersRes = Invoke-GrafanaApi -Method "GET" -Uri "/api/teams/$TeamId/members"
    
    $IsMember = $false
    if ($MembersRes.Status -eq 200 -and $MembersRes.Data) {
        foreach ($member in $MembersRes.Data) {
            if ($member.userId -eq $UserId) {
                $IsMember = $true
                break
            }
        }
    }

    if ($IsMember) {
        Write-Host "ℹ️ Пользователь уже состоит в команде '$Arg_TeamName'. Ничего не делаем." -ForegroundColor Gray
        $Success = $true
    }
    else {
        Write-Host "➕ Добавление пользователя в команду..."
        $AddBody = @{ userId = $UserId }
        
        $AddRes = Invoke-GrafanaApi -Method "POST" -Uri "/api/teams/$TeamId/members" -Body $AddBody
        
        if ($AddRes.Status -eq 200) {
            Write-Host "✅ Пользователь успешно добавлен в команду!" -ForegroundColor Green
            $Success = $true
        }
        elseif ($AddRes.Status -eq 400) {
            Write-Host "ℹ️ Пользователь уже в команде (ответ API 400)." -ForegroundColor Gray
            $Success = $true
        }
        else {
            throw "Ошибка добавления: $($AddRes.Raw)"
        }
    }

    if ($Success) { Write-Host "=== Успех ===" -ForegroundColor Green }
}
catch {
    $errorMessage = $_.Exception.Message
    Write-Host "=== ОШИБКА ===" -ForegroundColor Red
    Write-Host $errorMessage -ForegroundColor Red
    $Success = $false
}
finally {
    # Если скрипт завершился с ошибкой, отправляем email алерт
    if (-not $Success) {
        $emailSubject = "ALERT: Grafana Access Grant Script Failed ($Arg_Contour) - $Arg_Username"
        $emailBody = @"
Grafana Access Grant Script Execution Failed

Contour: $Arg_Contour
Username: $Arg_Username
Full Name (FIO): $Arg_FIO
Team: $Arg_TeamName
Requester Email: $Arg_RequesterEmail

Error Details:
$errorMessage

Timestamp: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Script: $($MyInvocation.MyCommand.Path)
"@
        
        Write-Host "📤 Отправка уведомления об ошибке..." -ForegroundColor Yellow
        Send-EmailAlert -ToAddress $Arg_RequesterEmail -Subject $emailSubject -Body $emailBody
    } else {
        Write-Host "Script completed successfully. No alert needed."
    }
}

exit $(if ($Success) { 0 } else { 1 })
