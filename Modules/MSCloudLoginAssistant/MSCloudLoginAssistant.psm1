<#
.SYNOPSIS
    The Test-MSCloudLogin function is used to assist with checking authentication status of and logging in to various Microsoft Cloud services, such as Azure, SharePoint Online, and SharePoint PnP.
.EXAMPLE
    Test-MSCloudLogin -Platform AzureAD -Verbose
.EXAMPLE
    Test-MSCloudLogin -Platform PnP
.PARAMETER Platform
    The Platform parameter specifies which cloud service for which we are testing the login state. Possible values are Azure, AzureAD, SharePointOnline, ExchangeOnline, SecurityComplianceCenter, MSOnline, PnP, PowerPlatforms, MicrosoftTeams, MicrosoftGraph and SkypeForBusiness.
.NOTES
    Created & maintained by the Microsoft365DSC Team, 2019-2020. (@BrianLala & @NikCharlebois)
.LINK
    https://github.com/Microsoft/MSCloudLoginAssistant
#>

function Test-MSCloudLogin
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet("Azure", "AzureAD", "SharePointOnline", "ExchangeOnline", `
                "SecurityComplianceCenter", "MSOnline", "PnP", "PowerPlatforms", `
                "MicrosoftTeams", "SkypeForBusiness", "MicrosoftGraph")]
        [System.String]
        $Platform,

        [Parameter()]
        [System.String]
        $ConnectionUrl,

        [Parameter()]
        [Alias("o365Credential")]
        [System.Management.Automation.PSCredential]
        $CloudCredential,

        [Parameter()]
        [System.String]
        $ApplicationId,

        [Parameter()]
        [System.String]
        $TenantId,

        [Parameter()]
        [System.String]
        $ApplicationSecret,

        [Parameter()]
        [System.String]
        $CertificateThumbprint,

        [Parameter()]
        [Switch]
        $UseModernAuth,

        [Parameter()]
        [SecureString]
        $CertificatePassword,

        [Parameter()]
        [System.String]
        $CertificatePath

    )
    if ($VerbosePreference -eq "Continue")
    {
        $verboseParameter = @{Verbose = $true }
    }
    else
    {
        $verboseParameter = @{ }
    }

    # If we specified the CloudCredential parameter then set the global o365Credential object to its value
    if ($null -ne $CloudCredential)
    {
        $Global:o365Credential = $CloudCredential
        $Global:DomainName = $Global:o365Credential.UserName.Split('@')[1]
    }

    if ($null -ne $Global:o365Credential)
    {
        # Required because of Connect-AzAccount which clears the password otherwise;
        $Global:o365Credential.Password.MakeReadOnly()
    }

    if ($null -eq $Global:UseModernAuth)
    {
        $Global:UseModernAuth = $UseModernAuth.IsPresent
    }

    Write-Verbose -Message "Trying to connect to platform {$Platform}"
    switch ($Platform)
    {
        'Azure'
        {
            Connect-MSCloudLoginAzure @verboseParameter
        }
        'AzureAD'
        {
            Connect-MSCloudLoginAzureAD @verboseParameter -ApplicationId $ApplicationId -TenantId $TenantId `
                -CertificateThumbprint $CertificateThumbprint
        }
        'SharePointOnline'
        {
            Connect-MSCloudLoginSharePointOnline @verboseParameter
        }
        'ExchangeOnline'
        {
            Connect-MSCloudLoginExchangeOnline @verboseParameter
        }
        'SecurityComplianceCenter'
        {
            Connect-MSCloudLoginSecurityCompliance @verboseParameter -CloudCredential $CloudCredential
        }
        'MicrosoftGraph'
        {
            Connect-MSCloudLoginMicrosoftGraph @verboseParameter -ApplicationId $ApplicationId -TenantId $TenantId `
                -CertificateThumbprint $CertificateThumbprint
        }
        'MSOnline'
        {
            Connect-MSCloudLoginMSOnline @verboseParameter
        }
        'PnP'
        {
            Connect-MSCloudLoginPnP -ConnectionUrl $ConnectionUrl @verboseParameter -ApplicationId $ApplicationId -TenantId $TenantId `
            -CertificateThumbprint $CertificateThumbprint -CertificatePassword $CertificatePassword -CertificatePath $CertificatePath
        }
        'MicrosoftTeams'
        {
            Connect-MSCloudLoginTeams @verboseParameter -ApplicationId $ApplicationId -TenantId $TenantId `
                -CertificateThumbprint $CertificateThumbprint
        }
        'SkypeForBusiness'
        {
            Connect-MSCloudLoginSkypeForBusiness @verboseParameter
        }
        'PowerPlatforms'
        {
            Connect-MSCloudLoginPowerPlatform @verboseParameter
        }
    }
}

function Get-SPOAdminUrl
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter()]
        [System.Management.Automation.PSCredential]
        $CloudCredential
    )

    Write-Verbose -Message "Connection to Azure AD is required to automatically determine SharePoint Online admin URL..."
    Test-MSCloudLogin -Platform AzureAD -CloudCredential $CloudCredential
    Write-Verbose -Message "Getting SharePoint Online admin URL..."
    $defaultDomain = Get-AzureADDomain | Where-Object { $_.Name -like "*.onmicrosoft.com" -and $_.IsInitial -eq $true } # We don't use IsDefault here because the default could be a custom domain

    if ($null -eq $defaultDomain)
    {
        $defaultDomain = Get-AzureADDomain | Where-Object { $_.Name -like "*.onmicrosoft.de" -and $_.IsInitial -eq $true }
        $domain = '.onmicrosoft.de'
        $tenantName = $defaultDomain[0].Name.Replace($domain, '')
        if ($Global:CloudEnvironment -eq 'Germany')
        {
            $spoAdminUrl = "https://$tenantName-admin.sharepoint.de"
        }
        elseif ($Global:CloudEnvironment -eq 'GCCHigh')
        {
            $spoAdminUrl = "https://$tenantName-admin.sharepoint.us"
        }
        Write-Verbose -Message "SharePoint Online admin URL is $spoAdminUrl"
        return $spoAdminUrl
    }
    else
    {
        $domain = '.onmicrosoft.com'
        $tenantName = $defaultDomain[0].Name.Replace($domain, '')
        $extension = 'sharepoint.com'
        if ($Global:CloudEnvironment -eq 'Germany')
        {
            $extension = 'sharepoint.de'
        }
        elseif ($Global:CloudEnvironment -eq 'GCCHigh')
        {
            $extension = 'sharepoint.us'
        }
        $spoAdminUrl = "https://$tenantName-admin.$extension"
        Write-Verbose -Message "SharePoint Online admin URL is $spoAdminUrl"
        return $spoAdminUrl
    }
}

function Get-AzureADDLL
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
    )
    [array]$AzureADModules = Get-Module -ListAvailable | Where-Object { $_.name -eq "AzureADPreview"}

    if ($AzureADModules.count -eq 0)
    {
        Throw "Can't find Azure AD DLL. Install the module manually 'Install-Module AzureADPreview'"
    }
    else
    {
        $AzureDLL = Join-Path (($AzureADModules | Sort-Object version -Descending | Select-Object -first 1).Path | Split-Path) Microsoft.IdentityModel.Clients.ActiveDirectory.dll
        return $AzureDLL
    }

}

function Get-TenantLoginEndPoint
{
    [CmdletBinding()]
    [OutputType([System.String])]
    Param(
        [Parameter(Mandatory = $True)]
        [System.String]
        $TenantName,
        [Parameter(Mandatory = $false)]
        [System.String]
        [ValidateSet('MicrosoftOnline', 'EvoSTS')]
        $LoginSource = "EvoSTS"
    )
    $TenantInfo = @{ }
    if ($LoginSource -eq "EvoSTS")
    {
        $webrequest = Invoke-WebRequest -Uri https://login.windows.net/$($TenantName)/.well-known/openid-configuration -UseBasicParsing
    }
    else
    {
        $webrequest = Invoke-WebRequest -Uri https://login.microsoftonline.com/$($TenantName)/.well-known/openid-configuration -UseBasicParsing
    }
    if ($webrequest.StatusCode -eq 200)
    {
        $TenantInfo = $webrequest.Content | ConvertFrom-Json
    }
    return $TenantInfo
}

function New-ADALServiceInfo
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)]
        [System.String]
        $TenantName,

        [Parameter(Mandatory = $True)]
        [System.String]
        $UserPrincipalName,

        [Parameter(Mandatory = $false)]
        [System.String]
        [ValidateSet('MicrosoftOnline', 'EvoSTS')]
        $LoginSource = "EvoSTS"
    )
    $AzureADDLL = Get-AzureADDLL
    if ([string]::IsNullOrEmpty($AzureADDLL))
    {
        Throw "Can't find Azure AD DLL"
        Exit
    }
    else
    {
        Write-Verbose -Message "AzureADDLL: $AzureADDLL"
        $tMod = [System.Reflection.Assembly]::LoadFrom($AzureADDLL)
    }

    $TenantInfo = Get-TenantLoginEndPoint -TenantName $TenantName
    if ([string]::IsNullOrEmpty($TenantInfo))
    {
        Throw "Can't find Tenant Login Endpoint"
        Exit
    }
    else
    {
        [string] $authority = $TenantInfo.authorization_endpoint
    }
    $PromptBehavior = [Microsoft.IdentityModel.Clients.ActiveDirectory.PromptBehavior]::Auto
    $Service = @{ }
    $Service["authContext"] = [Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext]::new($authority, $false)
    $Service["platformParam"] = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters" -ArgumentList $PromptBehavior
    $Service["userId"] = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.UserIdentifier" -ArgumentList $UserPrincipalName, "OptionalDisplayableId"

    Write-Verbose -Message "Current Assembly for AD AuthenticationContext: $([Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext].Assembly | Out-String)"

    return $Service
}

function Get-AuthHeader
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)]
        [System.String]
        $UserPrincipalName,
        [Parameter(Mandatory = $True)]
        [Alias("RessourceURI")] # For backward compat with anything using the misspelled parameter
        $ResourceURI,
        [Parameter(Mandatory = $True)]
        $clientId,
        [Parameter(Mandatory = $True)]
        [System.String]
        $RedirectURI
    )
    if ($null -eq $Global:ADALServicePoint)
    {
        $TenantName = $UserPrincipalName.split("@")[1]
        $Global:ADALServicePoint = New-ADALServiceInfo -TenantName $TenantName -UserPrincipalName $UserPrincipalName
    }

    try
    {
        Write-Debug "Looking for a refresh token"
        $authResult = $Global:ADALServicePoint.authContext.AcquireTokenSilentAsync($ResourceURI, $clientId)
        if ($null -eq $authResult.result)
        {
            $RedirectURI = [System.Uri]::new($RedirectURI)
            $authResult = $Global:ADALServicePoint.authContext.AcquireTokenAsync($ResourceURI, $clientId, $RedirectURI, $Global:ADALServicePoint.platformParam, $Global:ADALServicePoint.userId, "", "")
        }
        $AuthHeader = $authResult.result.CreateAuthorizationHeader()
    }
    catch
    {
        Throw "Can't create Authorization header: $_"
    }
    Return $AuthHeader
}

function Get-AccessToken
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)]
        $TargetUri,

        [Parameter(Mandatory = $True)]
        $AuthUri,

        [Parameter(Mandatory = $True)]
        $ClientId,

        [Parameter(Mandatory = $False)]
        [System.Management.Automation.PSCredential]
        $Credentials
    )

    try
    {
        Write-Verbose "There was no existing Access Token for $ClientId. Requesting a new one from $TargetUri"
        $AzureADDLL = Get-AzureADDLL
        if ([string]::IsNullOrEmpty($AzureADDLL))
        {
            throw "Can't find Azure AD DLL"
        }
        [System.Reflection.Assembly]::LoadFrom($AzureADDLL) | Out-Null

        $context = [Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext]::new($AuthUri, $false, [Microsoft.IdentityModel.Clients.ActiveDirectory.TokenCache]::DefaultShared)

        Write-Verbose -Message "AuthURI = $AuthURI"
        Write-Verbose -Message "TargetURI = $TargetUri"
        Write-Verbose -Message "ClientID = $ClientID"
        Write-Verbose -Message "Content = $context"
        $authResult = $context.AcquireTokenSilentAsync($TargetUri, $ClientId)
        $AccessToken = $authResult.result.AccessToken

        if ([System.String]::IsNullOrEmpty($AccessToken))
        {
            $jobName = "AcquireTokenAsync" + (New-Guid).ToString()
            Start-Job -Name $jobName -ScriptBlock {
                Param(
                    [Parameter(Mandatory = $True)]
                    $TargetUri,

                    [Parameter(Mandatory = $True)]
                    $AuthUri,

                    [Parameter(Mandatory = $True)]
                    $ClientId,

                    [Parameter(Mandatory = $False)]
                    [System.Management.Automation.PSCredential]
                    $Credentials
                )
                # Load AAD Assemblies
                $AzureADDLL = Get-AzureADDLL
                if ([string]::IsNullOrEmpty($AzureADDLL))
                {
                    throw "Can't find Azure AD DLL"
                }
                [System.Reflection.Assembly]::LoadFrom($AzureADDLL) | Out-Null

                $UserPasswordCreds = [Microsoft.IdentityModel.Clients.ActiveDirectory.UserPasswordCredential]::new($Credentials.UserName, $Credentials.Password)
                $context = [Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext]::new($AuthUri, $false, [Microsoft.IdentityModel.Clients.ActiveDirectory.TokenCache]::DefaultShared)
                $authResult = $context.AcquireTokenSilentAsync($TargetUri, $ClientId)

                if ($null -eq $authResult.result)
                {
                    $authResult = [Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContextIntegratedAuthExtensions]::AcquireTokenAsync($context, $targetUri, $ClientId, $UserPasswordCreds)
                }
                $token = $authResult.result.AccessToken
                return $token
            } -ArgumentList @($targetUri, $AuthUri, $ClientId, $Credentials) | Out-Null
            $job = Get-Job | Where-Object -FilterScript {$_.Name -eq $jobName}
            do
            {
                Start-Sleep -Seconds 1
            } while ($job.JobStateInfo.State -ne "Completed")
            $AccessToken = Receive-Job -Name $jobName
        }
        Write-Verbose "Token Found --> $AccessToken"
        return $AccessToken
    }
    catch
    {
        Write-Verbose $_
    }
}

function Get-SkypeForBusinessServiceEndpoint
{
    [CmdletBinding()]
    [OutputType([Uri])]
    param(
        [Parameter(Mandatory = $true)]
        [System.String]
        $TargetDomain
    )
    $overrideDiscoveryUri = "http://lyncdiscover." + $TargetDomain;
    $desiredLink = "External/RemotePowerShell";
    $liveIdUrl = $overrideDiscoveryUri.ToString() + "?Domain=" + $TargetDomain

    $xml = Get-RTCXml -Url $liveIdUrl
    $root = $xml.AutodiscoverResponse.Root

    $domain = $root.Link | Where-Object -FilterScript { $_.Token -eq 'domain' }
    if ($null -eq $domain)
    {
        $redirect = $root.Link | Where-Object -FilterScript { $_.Token -eq 'redirect' }

        if ($null -eq $redirect)
        {
            throw "Could not properly retrieve the Skype for Business service endpoint for $TargetDomain"
        }

        while ($null -ne $redirect)
        {
            $xml = Get-RTCXml -Url $redirect.href
            $root = $xml.AutodiscoverResponse.Root
            $domain = $root.Link | Where-Object -FilterScript { $_.Token -eq 'domain' }
            if ($null -eq $domain)
            {
                $redirect = $root.Link | Where-Object -FilterScript { $_.Token -eq 'redirect' }
            }
            else
            {
                $redirect = $null
            }
        }
    }
    $xml = Get-RTCXml -Url $domain.href
    $endpoint = $xml.AutodiscoverResponse.Domain.Link | Where-Object -FilterScript { $_.token -eq $desiredLink }
    $endpointUrl = $endpoint.href.Replace("/OcsPowershellLiveId", "/OcsPowershellOAuth")
    return [Uri]::new($endpointUrl)
}

function Get-RTCXml
{
    [CmdletBinding()]
    [OutputType([Xml])]
    param(
        [Parameter(Mandatory = $true)]
        [System.String]
        $Url
    )

    $request = [System.Net.WebRequest]::Create($Url);
    $request.set_Accept("application/vnd.microsoft.rtc.autodiscover+xml;v=1");
    $response = $request.GetResponse()
    $arg = [System.IO.StreamReader]::new($response.GetResponseStream()).ReadToEnd();
    $xml = [Xml]$arg
    return $xml
}

function Get-SkypeForBusinessAccessInfo
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Uri]
        $PowerShellEndpointUri
    )

    try
    {
        $response = [System.Net.HttpWebResponse] ([System.Net.HttpWebRequest] [System.Net.WebRequest]::Create($PowerShellEndpointUri)).GetResponse();
    }
    catch [System.Net.WebException]
    {
        $response = ([System.Net.WebException]$_.Exception).Response
    }
    $header = $response.Headers["WWW-Authenticate"]

    # Get ClientID
    $start = $header.IndexOf("client_id=") + 11
    $end = $header.IndexOf("`"", $start)

    $clientId = $null
    if ($end -gt $start)
    {
        $clientId = $header.Substring($start, $end - $start)
    }

    # Get Auth Url
    $start = $header.IndexOf("authorization_uri=") + 19
    $end = $header.IndexOf("`"", $start)

    $authUrl = $null
    if ($end -gt $start)
    {
        $authUrl = $header.Substring($start, $end - $start)
    }

    $result = @{
        ClientID = $clientId
        AuthUrl  = $authUrl
    }
    return $result
}

function Get-PowerPlatformTokenInfo
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.String]
        $Audience,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $Credentials
    )

    $jobName = 'AcquireTokenAsync' + (New-Guid).ToString()
    Start-Job -Name $jobName -ScriptBlock {
        Param(
            [Parameter(Mandatory = $true)]
            [System.Management.Automation.PSCredential]
            $O365Credentials,

            [Parameter(Mandatory = $true)]
            [System.String]
            $Audience
        )
        try
        {
            $WarningPreference = 'SilentlyContinue'
            Import-Module -Name 'Microsoft.PowerApps.Administration.PowerShell' -Force
            $authContext = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext("https://login.windows.net/common");
            $credential = [Microsoft.IdentityModel.Clients.ActiveDirectory.UserCredential]::new($O365Credentials.Username, $O365Credentials.Password)
            $authResult = $authContext.AcquireToken($Audience, "1950a258-227b-4e31-a9cf-717495945fc2", $credential);

            $JwtToken = $authResult.IdToken
            $tokenSplit = $JwtToken.Split(".")
            $claimsSegment = $tokenSplit[1].Replace(" ", "+");

            $mod = $claimsSegment.Length % 4
            if ($mod -gt 0)
            {
                $paddingCount = 4 - $mod;
                for ($i = 0; $i -lt $paddingCount; $i++)
                {
                    $claimsSegment += "="
                }
            }
            $decodedClaimsSegment = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($claimsSegment))
            $claims = ConvertFrom-Json $decodedClaimsSegment
        }
        catch
        {
            $_ | Out-File "$env:temp\MSCloudLoginAssistant_Error.txt"
        }
        return @{
            JwtToken     = $JwtToken
            Claims       = $claims
            RefreshToken = $authResult.RefreshToken
            AccessToken  = $authResult.AccessToken
            ExpiresOn    = $authResult.ExpiresOn
        }
    } -ArgumentList @($Credentials, $Audience) | Out-Null

    $job = Get-Job | Where-Object -FilterScript { $_.Name -eq $jobName }
    do
    {
        Start-Sleep -Seconds 1
    } while ($job.JobStateInfo.State -ne "Completed")
    $TokenInfo = Receive-Job -Name $jobName
    return $TokenInfo
}

function Test-MSCloudLoginCommand
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    Param(
        [Parameter(Mandatory = $true)]
        [System.String]
        $Command
    )

    try
    {
        $testResult = Invoke-Command $Command
        return $true
    }
    catch
    {
        return $false
    }
}

function Get-CloudEnvironmentInfo
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.PSCredential]
        $Credentials
    )

    try
    {
        $tenantName = $Credentials.UserName.Split('@')[1]
        $response = Invoke-WebRequest -Uri "https://login.microsoftonline.com/$tenantName/v2.0/.well-known/openid-configuration" -Method Get

        $content = $response.Content
        $result = ConvertFrom-Json $content
        return $result
    }
    catch
    {
        throw $_
    }
}

function Get-TenantDomain
{
    param(
        [Parameter(Mandatory = $true)]
        [System.String]
        $ApplicationId,

        [Parameter(Mandatory = $true)]
        [System.String]
        $TenantId,

        [Parameter(Mandatory = $true)]
        [System.String]
        $CertificateThumbprint
    )

    Test-MSCloudLogin -Platform AzureAD -ApplicationId $ApplicationId -TenantId $TenantId -CertificateThumbprint $CertificateThumbprint

    $domain = Get-AzureADDomain  | where-object {$_.IsInitial -eq $True} | select Name

    if ($null -ne $domain){

        return $domain.Name.split(".")[0]
    }
}

