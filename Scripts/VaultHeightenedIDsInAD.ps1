#Author: Josh Suchovsky
#Date: 21Feb2018
#Purpose: To pull all Heightened IDs from CyberArk and pull all the heightened IDs from all supported domains.  Compares the accounts
#		  and vaults any account not currently vaulted and emails the individuals
#Notes:  This script uses PoShPACLI modules from, https://github.com/pspete/PoShPACLI
#Version: 3.4
#	Added: PACLiSessionID to PACLI commands
#	Added: Error handling to the CyberArk commands that get the safes, users, and heightenedIDs
#	Added: A block to vaulting over 100 accounts, has to be overridden

#Variables to be set for Script (Change to fit your environment)
    #Where would you like your reports saved
    $myResults = 'D:\PowerShell\Results'

    #Vault to login too
    $Vault = "<VaultName>"

    #Vault Address we are logging into
    $VaultAddress = "<IPAddress>"

    #PACLI session to use
    $PACLISessionID = 3

    #PACLI User that will be used to log into the Vault
    $PACLIUser = "PACLIUserAccount"

    #The object name of the PACLI account used to login
    $PACLIObjectName = "PACLIUserAccountObjectName"

    #The safe of the PACLI user used to login
    $PACLISafe = "PACLIUserAccountSafe"

    #The Application Name that grants the server permissions to use PACLI Account
    $PACLIAppID = "CyberArkApplicationID"

    #PACLI Folder Location
    $PACLIFolder = "D:\Program Files (x86)\CyberArk\PACLI"

    #CyberArk Ldap Connector Name; This is the primary connector use to connect to Active Directory
    $CyberArkLDAPConnector = "Domain Authentication"

    #CyberArk PVWA URL; For customer access
    $CyberArkURL = "https://cyberark.company.com"

    #Email address to send the report of actions taken and issues
    $To = "cyberark@company.com"

    #Email address to send from
    $fromEmail = "NoNotReply@company.com"

    #Update to your company's SMTP host 
    $SMTPMail = "SMTP.company.com"

    #Email to end users
    #Email will be sent to userid@company.com
    $EmailDomain = "company.com"

    #Folder in safe where accounts are created
    $Folder = "root"

    #Finding Accounts
    #CyberArk Object Names starting with SIDS
    $SIDs = "S-1-5-21*"

    #Regex to find accounts in Active Directory and CyberArk
    $AccountRegex1 = '~\b[haHA]{2}[0-9]{6}[adAD]{2}'
    $AccountRegex2 = '\b[haHA]{2}[0-9]{6}[adAD]{2}'
    $AccountSearchAD1 = "~HA******AD"
    $AccountSearchAD2 = "HA******AD"

    #User Safes to search
    $UserSafe1 = "PPA-Domain-*"
    $UserSafe2 = "PPA-Domain2-*"
    $UserSafe3 = "PPA-Domain3-*"
    $UserSafe4 = "PPA-Domain4-*"

    #Standard Naming Standard for User safes
    # Example: PPA-Domain-UserID
    $SafeStandard = "PPA-Domain"

    #Get BCC'd on Customer emails; Set to True
    $BCC = $False

#Variables used to Error Handling
$CyberArkCountOverride = $False
$CyberArkIssue = $False
$IssuesFound = $False

#Variables used to identify script when emailing and using scheduled tasks
$StartTime = Get-Date
$scriptName = $MyInvocation.MyCommand.Name
$scriptUser = whoami

#Functions used in script
function Email{
#Function to Email results, can include files
    Param(
        [Parameter(Mandatory=$True)]
        [string]$ToEmail,
        [Parameter(Mandatory=$True)]
        [string]$Subject,
        [Parameter(Mandatory=$True)]
        [string]$Message,
        [Parameter(Mandatory=$False)]
        [string]$CC,
        [Parameter(Mandatory=$False)]
        [string]$BCC,
        [Parameter(Mandatory=$False)]
        [string]$File,
        [Parameter(Mandatory=$False)]
        [switch]$CustomerEmail,
        [Parameter(Mandatory=$False)]
        #Update to your company's email address
        [string]$fromEmail=$fromEmail
    )
    #Update to your company's SMTP host, variable placed at top of script
    #$SMTPMail = "SMTP.company.com"
    
    if(!$CustomerEmail){
        #Adds to any non customer email, what server it came from, script name, and what user it ran as
        $Message += "<br /><br /><br /><br /><br />Script was ran from: $env:computername<br />Script Name: $scriptName<br />Ran as: $scriptUser"
    }
    if($CC){
        if($BCC){
            if(![string]::IsNullOrEmpty($File)){
                Send-MailMessage -From $fromEmail -To $ToEmail -CC $CC -Bcc $BCC -Subject $Subject -Body $Message -SMTPServer $SMTPMail -Attachments $File -BodyAsHtml
            }
            else{
                Send-MailMessage -From $fromEmail -To $ToEmail -CC $CC -Bcc $BCC -Subject $Subject -Body $Message -SMTPServer $SMTPMail -BodyAsHtml
            }
        }
        else{
            if(![string]::IsNullOrEmpty($File)){
                Send-MailMessage -From $fromEmail -To $ToEmail -CC $CC -Subject $Subject -Body $Message -SMTPServer $SMTPMail -Attachments $File -BodyAsHtml
            }
            else{
                Send-MailMessage -From $fromEmail -To $ToEmail -CC $CC -Subject $Subject -Body $Message -SMTPServer $SMTPMail -BodyAsHtml
            }
        }
    }
    else{
        if($BCC){
            if(![string]::IsNullOrEmpty($File)){
                Send-MailMessage -From $fromEmail -To $ToEmail -Bcc $BCC -Subject $Subject -Body $Message -SMTPServer $SMTPMail -Attachments $File -BodyAsHtml
            }
            else{
                Send-MailMessage -From $fromEmail -To $ToEmail -Bcc $BCC -Subject $Subject -Body $Message -SMTPServer $SMTPMail -BodyAsHtml
            }
        }
        else{
            if(![string]::IsNullOrEmpty($File)){
                Send-MailMessage -From $fromEmail -To $ToEmail -Subject $Subject -Body $Message -SMTPServer $SMTPMail -Attachments $File -BodyAsHtml
            }
            else{
                Send-MailMessage -From $fromEmail -To $ToEmail -Subject $Subject -Body $Message -SMTPServer $SMTPMail -BodyAsHtml
            }
        }
    }
}

Function Send-Error ($sub, $msg) {
    #Update to your work email or team distribution list
    . Email -ToEmail $To -Subject $sub -Message $msg
}

Function ExportVariable ($Export, $filename){
#Function to check if a file is open and if it is not, export variable results to it
    $fileclosed = $False
    if($Export){
        #Do this until you are able to write to the file
        Do{
            #Error handling
            Try{
                #Export the variable to a file in \PowerShell\Results
                $Export | export-csv $myResults\$filename-$(get-date -f ddMMMyyyy).csv -noType
                #If it is successful, Write-Output out the path to the window
                if ($?){
                    $fileclosed = $True
                    $file =  "$myResults\$filename-$(get-date -f ddMMMyyyy).csv"
                    Write-Output "`nResults have been exported to, $myResults\$filename-$(get-date -f ddMMMyyyy).csv"
                    $fileResults = "File was exported to $file"
                }
            }
            Catch [System.IO.IOException]{
                #If it failed, Write-Output to the window and inform the user to close the file
                $fileclosed = $False
                Write-Output "`nThe file, $myResults\$filename-$(get-date -f ddMMMyyyy).csv, is currently open.  Please close it to export the results"
                Read-Host -Prompt "Press Enter to continue"
            }
        }until ($fileclosed -eq $True)
    }
    else{
        Write-Output "Did not find any results"
        $fileResults = "Did not find any results"
        $file =  ""
    }
}

function DomainsSupported {
    #Domains need to be listed here and should match the switch statement in the SelectDomain Function
    $SupportedDomains = ("Domain1", "Domain2", "Domain3")
}
function SelectDomain ($Domain){
    #This function will load a domain and set the the location to it.  This enables you to run AD commands against the domain
    #. StoredDomains
    
    $DomainSelected = "True"
    $LoginError = $FALSE
    Do{
        #Will keep running the code inside the DO until $DomainSelected is True.
        if ((($Domain -eq $null) -or ($Domain -eq "")) -or ($DomainSelected -eq "False")){
            #Checks to see if the function was passed a domain, if not asks for the domain
            $Domain = (Read-Host -Prompt "Select the domain? Supported Domains are: $SupportedDomains")
        }
        $DomainSelected = "False"
        $ADDrive = Get-PSDrive | Select-Object Name #Gets a list of all the current PSDrives
        #foreach($SD in $Domain){ #Loads commonly used variables for the domains
        if($Domain){
        #Loads commonly used variables for the domains
            switch ($Domain.ToLower()){
                domain1 {
                    Write-Output "Logging into $Domain" >>$Logging
                    #Domain Information
                    $FQDN = "child.domain1.com"
                    $LDAPFQDN = "DC=child,DC=domain1,DC=com"
                    $NetBios = "NetBiosName1"
                    #DCServer variables should be FQDN, unless the domain is at a functional level below Windows 2008R2.  If below, set to a DC with Windows 2008R2 or highier installed.
                    $DCServer = $FQDN
                    $DomainSelected = "True"
                    #DomainName used for reports and exported with vaulting results
                    $DomainName = "DomainName"
                    #Account used to login to domain to read Active Directory
                    #Safe account is stored in
                    $SrcAcctSafe = "Domain1_Safe"

                    #CyberArk Application that has permissions to safe
                    $SrcAcctAppID = "App1"

                    #CyberArk Object Name of Account
                    $SrcAcctObject = "WinDomain-Bind-Domain1-ServiceAccount1"

                    #Account Username
                    $SrcAcct = "ServiceAccount1"

                    #Platform to use when vaulting heightened accounts in Domain
                    $UserPlatformID = "WinDomain-PPA-Domain1"
                }
                Domain2{
                    Write-Output "Logging into $Domain" >>$Logging
                    #Domain Information
                    $FQDN = "domain2.com"
                    $LDAPFQDN = "DC=domain2,DC=com"
                    $NetBios = "NetBiosName2"
                    #DCServer variables should be FQDN, unless the domain is at a functional level below Windows 2008R2.  If below, set to a DC with Windows 2008R2 or highier installed.
                    $DCServer = $FQDN
                    $DomainSelected = "True"
                    #DomainName used for reports and exported with vaulting results
                    $DomainName = "DomainName"
                    #Account used to login to domain to read Active Directory
                    #Safe account is stored in
                    $SrcAcctSafe = "Domain2_Safe"

                    #CyberArk Application that has permissions to safe
                    $SrcAcctAppID = "App1"

                    #CyberArk Object Name of Account
                    $SrcAcctObject = "WinDomain-Bind-Domain1-ServiceAccount2"

                    #Account Username
                    $SrcAcct = "ServiceAccount2"

                    #Platform to use when vaulting heightened accounts in Domain
                    $UserPlatformID = "WinDomain-PPA-Domain2"
                }
                Domain3{
                    Write-Output "Logging into $Domain" >>$Logging
                    $FQDN = "domain3.local"
                    $LDAPFQDN = "DC=domain3,DC=local"
                    $NetBios = "NetBiosName3"
                    #DCServer variables should be FQDN, unless the domain is at a functional level below Windows 2008R2.  If below, set to a DC with Windows 2008R2 or highier installed.
                    $DCServer = "DC1.domain3.local"
                    $DomainSelected = "True"
                    #DomainName used for reports and exported with vaulting results
                    $DomainName = "DomainName"
                    #Account used to login to domain to read Active Directory
                    #Safe account is stored in
                    $SrcAcctSafe = "Domain3_Safe"

                    #CyberArk Application that has permissions to safe
                    $SrcAcctAppID = "App1"

                    #CyberArk Object Name of Account
                    $SrcAcctObject = "WinDomain-Bind-Domain1-ServiceAccount3"

                    #Account Username
                    $SrcAcct = "ServiceAccount3"

                    #Platform to use when vaulting heightened accounts in Domain
                    $UserPlatformID = "WinDomain-PPA-Domain3"
                }
                default{
                #If nothing matches, display the supported domains and ask again
                    Write-Output "Please select a supported domain."
                    $DomainSelected = "False"
                    $Domain = ""
                }
            }
            $SkipDomain = ""
            if($Domain){
            #If the variable is not null, process the code
                Do{
                #Do until the user is able to login
                    if($LoginError -eq $TRUE){
                        #Checks to see if there was a previous bad attempt to login
                        $SkipDomain = $True
                        $subject = "Scripting Server Error:  Failed to login to $Domain"
                        $msg = "Failed to login to $Domain with $($Credential.UserName).`n`n Error: $($error[0].Exception.GetType().FullName)"
                        Send-Error $subject $msg
                    }
                    if ($ADDrive.name -notcontains $Domain){
                        #Checks to see if the PSDrive already exists for the domain
                        Try{
                            . LogIn -Safe $SrcAcctSafe -AppID $SrcAcctAppID -ObjectName $SrcAcctObject -ServiceAccount $SrcAcct -NetBios $NetBios
                            #Creates a new PSDrive for the domain
                            New-PSDrive -Name $Domain -PSProvider ActiveDirectory -root "" -server $DCServer -Credential $Credential -ErrorAction "Stop" > $null
                        }
                        Catch [System.Security.Authentication.AuthenticationException]{
                            #Captures bad passwords
                            Write-Output "`n`nError: Could not log into the domain, $domain."
                            Write-Output $Error[0].Exception
                            $SkipDomain = $True
                            $LoginError = $TRUE
                            $subject = "Scripting Server Error:  Failed to login to $Domain"
                            $msg = "Failed to login to $Domain with $($Credential.UserName).<br /><br />Error: $($error[0].Exception.GetType().FullName)"
                            Send-Error $subject $msg
                        }
                        Catch [System.UriFormatException]{
                            Write-Output "`nError: $domain, is not fully supported at this time"
                            $LoginError = $True
                            $SkipDomain = $True
                            $subject = "Scripting Server Error:  Failed to login to $Domain"
                            $msg = "Failed to login to $Domain with $($Credential.UserName).<br /><br />Error: $($error[0].Exception.GetType().FullName)"
                            Send-Error $subject $msg
                        }
                        Catch{
                            Write-Output "`nUnkown Error in $domain"
                            $LoginError = $True
                            $SkipDomain = $True
                            $subject = "Scripting Server Error:  Failed to login to $Domain"
                            $msg = "Failed to login to $Domain with $($Credential.UserName).<br /><br />Error: $($error[0].Exception.GetType().FullName)"
                            Send-Error $subject $msg
                        }
                    }
                    if($LoginError -eq $FALSE){
                    #Checks to make sure there is no previous failures, if so, skips
                        Try{
                            #Changes the location to the domain
                            Set-Location "${Domain}:" -ErrorAction "Stop"
                            #Set-Location "${Domain}:" -ErrorAction "SilentlyContinue" #Changes the location to the domain
                        }
                        Catch [System.Management.Automation.DriveNotFoundException] {
                            #Captures the AD drive missing
                            Write-Output "Error: Unable to find $domain"
                            Write-Output $Error[0].Exception
                            $LoginError = $TRUE
                            $subject = "Scripting Server Error:  Failed to login to $Domain"
                            $msg = "Failed to login to $Domain with $($Credential.UserName).<br /><br />Error: $($error[0].Exception.GetType().FullName)"
                            Send-Error $subject $msg
                        }
                    }
                }until ($LoginError -eq $FALSE -Or $SkipDomain -eq $TRUE)
            }
        }
    }until ($DomainSelected -eq "True")
}
Function PACLILoad {
	Param(
		[Parameter(Mandatory=$True)]
		[string]$Vault,
		[Parameter(Mandatory=$True)]
		[string]$VaultAddress,
		[Parameter(Mandatory=$True)]
		[int]$PACLISessionID
	)
	Import-Module PoShPACLI
	Initialize-PoShPACLI -pacliFolder $PACLIFolder > $Null
	
	Try{
		Start-PVPacli -SessionID $PACLISessionID -ErrorAction Stop > $Null
	}
	Catch [Microsoft.PowerShell.Commands.WriteErrorException] {
		Write-Output "PACLI already started"
	}
	Catch {
		Write-Output "PACLI failed to start"
		$Subject = "PACLI Failed to Start"
		$Message = "Failed to start PACLI.<br/>$($Error[0].Exception.Message)"
		Send-Error $Subject $Message
	}
	Try{
		New-PVVaultDefinition -vault $Vault -sessionID $PACLISessionID -address $VaultAddress -ErrorAction Stop > $Null
	}
	Catch [Microsoft.PowerShell.Commands.WriteErrorException] {
		Write-Output "Vault definition already exists"
	}
}

Function PACLIAIM-Logon {
	Param(
		[Parameter(Mandatory=$True)]
		[string]$PACLIUser,
		[Parameter(Mandatory=$True)]
		[int]$PACLISessionID,
		[Parameter(Mandatory=$True)]
		[string]$PACLIUserSafe,
		[Parameter(Mandatory=$True)]
		[string]$PACLIObjectName,
		[Parameter(Mandatory=$True)]
		[string]$AppID
	)
	$PACLIConnection = ""
	#Logon To AIM
	. LogIn -Safe $PACLIUserSafe -AppID $AppID -ObjectName $PACLIObjectName -ServiceAccount $PACLIUser
	Try{
		Write-Output "Logging into CyberArk"
		$PACLIConnection = Connect-PVVault -Vault $Vault -sessionID $PACLISessionID -User $PACLIUser -Password $($Credential.Password) -ErrorAction Stop
	}
	Catch{
		Write-Output "Failed to Login"
		$Subject = "PACLI Failed to Login"
		$Message = "Failed to login using PACLI.<br/>$($Error[0].Exception.Message)"
		Send-Error $Subject $Message
		$PACLIConnection = $False
	}
	$Credential = ""
}

. DomainsSupported

#Run function to load CyberArk values
. PACLILoad -Vault $Vault -VaultAddress $VaultAddress -PACLISessionID $PACLISessionID

#Logs into CyberArk using AIM to pull the credentials and logs in with PACLI
Write-Output "Logging into CyberArk"
. PACLIAIM-Logon -PACLIUser $PACLIUser -PACLIUserSafe $PACLISafe -PACLIObjectName $PACLIObjectName -AppID $PACLIAppID -PACLiSessionID $PACLiSessionID

if ($PACLIConnection) {
    #Searching all Safes in CyberArk and getting all objects in safes that match User safes
    Try {
        $SafesList = ""
        Write-Output "Getting all Safes"
        $SafesList = Get-PVSafeList -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -ErrorAction Stop | Where-Object {(($_.Safename -like $UserSafe1) -Or ($_.Safename -like $UserSafe2) -Or ($_.Safename -like $UserSafe3) -Or ($_.Safename -like $UserSafe4))} | Sort-Object Safename
        $UserList = ""
        Write-Output "Getting all CyberArk Users"
        $UserList = Get-PVUserList -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -ErrorAction Stop | Where-Object {(($_.Username -NotLike "SVC*") -Or ($_.Username -NotLike "Vault*") -Or ($_.Username -ne "Vault Users Mapping") -Or ($_.Username -NotLike "src*") -Or ($_.Username -NotLike "Engineers*") -Or ($_.Username -NotLike "PSMPT*") -Or ($_.Username -NotLike "ActiveDirectory*") -Or ($_.Username -NotLike "Support*") -Or ($_.Username -NotLike "Master*") -Or ($_.Username -NotLike "PasAdmin*") -Or ($_.Username -NotLike "NAIM*") -Or ($_.Username -NotLike "WLP*") -Or ($_.Username -NotLike "Auditor*") -Or ($_.Username -NotLike "Backup*") -Or ($_.Username -NotLike "Avatar*") -Or ($_.Username -NotLike "Administrator*") -Or ($_.Username -NotLike "aiminstall*") -Or ($_.Username -NotLike "CyberArk*") -Or ($_.Username -NotLike "CSA*") -Or ($_.Username -NotLike "FC_Demo*") -Or ($_.Username -NotLike "PASUpgrade*") -Or ($_.Username -NotLike "Operator*") -Or ($_.Username -NotLike "Provisioner*") -Or ($_.Username -NotLike "PSMApp*") -Or ($_.Username -NotLike "PSMGw*") -Or ($_.Username -NotLike "PSMLiveSessionTerminators*") -Or ($_.Username -NotLike "PSMMaster*") -Or ($_.Username -NotLike "PVWA*") -Or ($_.Username -NotLike "PSMGw*")) -And ($_.Location -eq "\Users") -And ($_.LDAPUser -eq "YES")}
    }
    Catch {
        $CyberArkIssue = $True
        $CyberArkErrorDetails = $($Error[0].Exception.Message)
    }
    $SIDs = @()
    $VaultedHeightenedIDs = @()
    #Goes through all the safes and pulls all of the objects in them
    Write-Output "Getting all Objects out of User Safes"
    Try {
        foreach ($Safe in $($SafesList.Safename)) {
            Open-PVSafe -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $Safe > $Null
            $IDs = ""
            $IDs = Get-PVFileList -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $Safe -Folder $Folder -ErrorAction Stop | Select-Object Filename
            $Matches = ""
            #Goes through all of the objects and looks for objects that have a heightened id in the filename
            foreach ($ID in $IDs) {
                if (($ID -match $AccountRegex1) -or ($ID -match $AccountRegex2)) {
                    #Pulls the Domain Information from the first part of the filename
                    $pos = ""
                    $AccountDomain = ""
                    $pos = $ID.Filename.IndexOf("-")
                    $AccountDomain = $ID.Filename.Substring(0, $pos)
                    $VaultedHeightenedIDs += [pscustomobject]@{
                        ID            = $Matches.Values
                        AccountDomain = $AccountDomain
                    }
                }
                if ($($ID.Filename) -like $SIDs) {
                    $SIDs += $ID
                }
            }
            Close-PVSafe -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $Safe > $Null
        }
    }
    Catch {
        $CyberArkIssue = $True
        $CyberArkErrorDetails = $($Error[0].Exception.Message)
    }
}
Disconnect-PVVault -vault $Vault -SessionID $PACLiSessionID -user $PACLIUser > $Null

if ($CyberArkIssue -eq $False) {
    # Expected filename, Domain-HeightenedAccount
    #Checking to see if any accounts are vaulted, but do not exist
    $TempVaultedHeightenedIDs = $VaultedHeightenedIDs

    #Pulling accounts from Active Directory and checking if accounts are vaulted
    $VaultedResults = @()
    if ($SafesList) {
        foreach ($Domain in $SupportedDomains) {
            #Logs into the domain that is listed in the $SupportedDomains variable in the Function DomainsSupported
            . SelectDomain $Domain
            Write-Output $Domain
            $VaultedAccounts = ""
            #Find Only Enabled Accounts, pulls extra fields Office and Mobile.  We kept standard IDs in one field and Tier level in the second
            $VaultedAccounts = Get-ADUser -Filter {(((SamAccountName -like $AccountSearchAD1) -Or (SamAccountName -like $AccountSearchAD2)) -And (enabled -eq $true))} -Properties Office, Mobile | Where-Object {(($_.SamAccountName -match $AccountRegex1) -Or ($_.SamAccountName -match $AccountRegex2))}
			
            #CyberArk IDs in the current domain
            $CyberArkIDsInDomain = ""
            $CyberArkIDsInDomain = $VaultedHeightenedIDs | Where-Object {($_.AccountDomain -Contains $Domain)}
			
            #Compares the accounts found in Active Directory to the accounts in CyberArk
            foreach ($Account in $VaultedAccounts) {
                if ($CyberArkIDsInDomain.ID -contains $Account.SamAccountName) {
                    Write-Output "Found Account $($Account.SamAccountName)"
                    $VaultedResults += [pscustomobject]@{
                        Domain     = $Domain
                        Account    = $Account.SamAccountName
                        Enabled    = $Account.Enabled
                        StandardID = $Account.Office
                        Vaulted    = $True
                        FirstName  = $Account.GivenName
                        LastName   = $Account.Surname
                        Tier       = $Account.Mobile
                        FQDN       = $FQDN
                        PlatformID = $UserPlatformID
                        NetBios    = $NetBios
                        DomainName = $DomainName
                    }
                    #Removes accounts that are active and vaulted, leaving accounts that are no longer active, but vaulted
                    $TempVaultedHeightenedIDs = $TempVaultedHeightenedIDs | Where-Object {(($_.ID -NotContains $($Account.SamAccountName)) -And ($_.AccountDomain -NotContains $Domain))}
                }
                elseif ($CyberArkIDsInDomain.ID -NotContains $Account.SamAccountName) {
                    Write-Output "Could not find $($Account.SamAccountName)"
                    $VaultedResults += [pscustomobject]@{
                        Domain     = $Domain
                        Account    = $Account.SamAccountName
                        Enabled    = $Account.Enabled
                        StandardID = $Account.Office
                        Vaulted    = $False
                        FirstName  = $Account.GivenName
                        LastName   = $Account.Surname
                        Tier       = $Account.Mobile
                        FQDN       = $FQDN
                        PlatformID = $UserPlatformID
                        NetBios    = $NetBios
                        DomainName = $DomainName
                    }
                }
            }
        }
        . ExportVariable $VaultedResults "VaultedAccounts-AllDomain"
        #If filenames are found that are SIDs, send an email to be corrected
        if ($SIDs) {
            $Subject = "SIDs Found in CyberArk"
            . ExportVariable $SIDs "AccountsListedbySIDs-AllDomain"
            . Email -ToEmail $To -Subject $Subject -Message $Message -File $File
        }

        #Processing
        #Log into the Main Domain, where everyone has a standard ID
        #This is used to pull users info, in all of my heightened IDs, we put the standard ID assoicated to it, in the Office field
        . SelectDomain "InsertDomain"

        #Builds a list of accounts not vaulted
        $NotVaulted = $VaultedResults | Where-Object {(($($_.Enabled) -eq $True) -AND ($($_.Vaulted) -eq $False))}

        #Built in controls to not vault more than 100 accounts without first acknowledging it. 
        #Prevent runtime errors and emailing your whole company
		if(($NotVaulted.count -lt 101) -or ($CyberArkCountOverride -eq $True)){
			$AccountsVaultedStatus = @()
            #Log back into CyberArk
			. PACLIAIM-Logon -PACLIUser $PACLIUser -PACLIUserSafe $PACLISafe -PACLIObjectName $PACLIObjectName -AppID $PACLIAppID -PACLiSessionID $PACLiSessionID

			foreach ($NewAccount in $NotVaulted) {
				#Find if safe exists, if not created it
				Write-Output "Testing account: $($NewAccount.Account)"
				#Pull standard ID info from the main domain
				$ADUser = ""
				$ADUser = Get-ADUser $($NewAccount.StandardID)
				#If user wasn't found, don't vault account, notify
				if (!$ADUser) {
					Write-Output "$Domain Account was not found"
					$NewSafeCreated = $False
					$UserSafe = ""
					$AccountVaulted = $False
					$AccountsVaultedStatus += [pscustomobject]@{
						Domain         = $($NewAccount.FQDN)
						StandardID     = $($NewAccount.StandardID)
						HeightenedID   = $($NewAccount.Account)
						NewSafe        = $NewSafeCreated
						Safe           = $UserSafe
						AccountVaulted = $AccountVaulted
						FileName       = ""
						LogonDomain    = ""
						Notes          = "$Domain Account was not found"
						DateVaulted    = $(get-date -f ddMMMyyyy)
					}
					$IssuesFound = $True
				}
				elseif ($ADUser.Enabled -eq $False) {
					#If standardID is disabled, don't vault account, notify
					Write-Output "$Domain Account is Disabled"
					$NewSafeCreated = $False
					$UserSafe = ""
					$AccountVaulted = $False
					$AccountsVaultedStatus += [pscustomobject]@{
						Domain         = $($NewAccount.FQDN)
						StandardID     = $($NewAccount.StandardID)
						HeightenedID   = $($NewAccount.Account)
						NewSafe        = $NewSafeCreated
						Safe           = $UserSafe
						AccountVaulted = $AccountVaulted
						FileName       = ""
						LogonDomain    = ""
						Notes          = "$Domain Disabled; verify user is terminated, have account disabled"
						DateVaulted    = $(get-date -f ddMMMyyyy)
					}
					$IssuesFound = $True
				}
				else {
					#If standard ID is found and enabled, vault user
					$UserSafe = ""
					$SafeSearch = ""
					#Search to see if user has a safe
					$SafeSearch = $SafesList | Where-Object {$_.Safename -eq "$SafeStandard-$($NewAccount.StandardID)"}
					
					Write-Output $($SafeSearch.Safename)
					$NewSafeCreated = $FALSE
					if ($SafeSearch) {
						$UserSafe = $SafeSearch.Safename
						#Check to see if safe has all required permissions
						Open-PVSafe -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe > $Null
						$SafePermissions = Get-PVSafeOwner -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -safePattern $UserSafe -ownerPattern *
						$UserPermissionFound = $False
						$PPAPermissionFound = $False
						# $SupportPermissionFound = $False
						# $CBAAdminPermissionFound = $False
						# $CBAOpsPermissionFound = $False
						# $CBASysOpsPermissionFound = $False
						# $CBAAdminURETPermissionFound = $False
						$PasswordManagerPermissionFound = $False
						
						Write-Output "User safe found"
						foreach ($Permission in $SafePermissions) {
							if ($Permission.Username -eq $($NewAccount.StandardID)) {
								$UserPermissionFound = $True
							}
							if ($Permission.Username -eq "PPA Safe Admin") {
								$PPAPermissionFound = $True
							}
							# if ($Permission.Username -eq "Support Group") {
							# 	$SupportPermissionFound = $True
							# }
							# if ($Permission.Username -eq "Admins") {
							# 	$CBAAdminPermissionFound = $True
							# }
							# if ($Permission.Username -eq "Ops") {
							# 	$CBAOpsPermissionFound = $True
							# }
							# if ($Permission.Username -eq "SysOps") {
							# 	$CBASysOpsPermissionFound = $True
							# }
							if ($Permission.Username -eq "passwordmanager") {
								$PasswordManagerPermissionFound = $True
							}
						}

						if ($UserPermissionFound -eq $False) {
							Write-Output "Adding user permission"
							Add-PVSafeOwner -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Owner $($NewAccount.StandardID) -Retrieve -List -usePassword -viewAudit -viewPermissions > $Null
						}
						if ($PPAPermissionFound -eq $False) {
							Write-Output "Adding PPA Safe Admin permission"
							Add-PVSafeOwner -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Owner "PPA Safe Admin" -Retrieve -Store -Delete -Administer -accessNoConfirmation -validateSafeContent -List -updateObjectProperties -usePassword -initiateCPMChange -initiateCPMChangeWithManualPassword -createFolder -deleteFolder -moveFrom -moveInto -viewAudit -viewPermissions -createObject -renameObject -supervise -backup -manageOwners -eventsList -addEvents -unlockObject > $Null
                        }
                        #May need to add what groups that you use to help manage users
						#if ($SupportPermissionFound -eq $False) {
							#Write-Output "Adding Support Group permission"
							#Add-PVSafeOwner -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Owner "Support Group" -List -initiateCPMChange > $Null
						#}
						#if ($CBAAdminPermissionFound -eq $False) {
							#Write-Output "Adding Admins permission"
							#Add-PVSafeOwner -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Owner "Admins" -Retrieve -Store -Delete -Administer -accessNoConfirmation -validateSafeContent -List -updateObjectProperties -usePassword -initiateCPMChange -initiateCPMChangeWithManualPassword -createFolder -deleteFolder -moveFrom -moveInto -viewAudit -viewPermissions -createObject -renameObject -supervise -manageOwners -eventsList -addEvents -unlockObject > $Null
						#}
						#if ($CBAOpsPermissionFound -eq $False) {
							#Write-Output "Adding Ops permission"
							#Add-PVSafeOwner -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Owner "Ops" -Retrieve -Store -Delete -Administer -accessNoConfirmation -validateSafeContent -List -usePassword -initiateCPMChange -moveFrom -moveInto -viewAudit -viewPermissions > $Null
						#}
						#if ($CBASysOpsPermissionFound -eq $False) {
							#Write-Output "Adding SysOps permission"
							#Add-PVSafeOwner -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Owner "SysOps" -Retrieve -Store -Delete -Administer -validateSafeContent -List -updateObjectProperties -usePassword -initiateCPMChange -createFolder -deleteFolder -moveFrom -moveInto -viewAudit -viewPermissions -createObject -renameObject -manageOwners -eventsList -addEvents -unlockObject > $Null
						#}
						if ($PasswordManagerPermissionFound -eq $False) {
							Write-Output "Adding passwordmanager permission"
							Add-PVSafeOwner -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Owner "passwordmanager" -Retrieve -Store -Delete -Administer -accessNoConfirmation -validateSafeContent -List -updateObjectProperties -usePassword -initiateCPMChange -initiateCPMChangeWithManualPassword -createFolder -deleteFolder -moveFrom -moveInto -viewAudit -viewPermissions -createObject -renameObject > $Null
						}
					}
					else {
						#Check to see if user exists in CyberArk, Add the user to CyberArk
						if ($UserList.Username -NotContains $($ADuser.SamAccountName)) {
                            Write-Output "Added user: $($ADuser.SamAccountName) to CyberArk"
                            #Grants the user the ability to logon to CyberArk
							Add-PVExternalUser -vault $Vault -SessionID $PACLiSessionID -user $PACLIUser -destUser $($NewAccount.StandardID) -ldapFullDN $($ADuser.DistinguishedName) -ldapDirectory $CyberArkLDAPConnector > $Null
						}
						#Create Safe
						Write-Output "No Safe Found, searched for $SafeStandard-$($NewAccount.StandardID)"
						#Write-Output "No Safe Found, searched for $UserSafe"
                        
                        #Will Create new safe in the format PPA-Domain-StandardID
						$UserSafe = "$SafeStandard-$($NewAccount.StandardID)"
						$Description = "Safe Owned By: $($NewAccount.StandardID), $($ADuser.DistinguishedName)"
						$Description = $Description.Substring(0, 83)
						#Create Safe and Open it
						New-PVSafe -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Location "\" -Description $Description -safeOptions 512 > $Null
						Open-PVSafe -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe > $Null
						#ADD CPM Permissions
						#PasswordMananger - User Accounts, Retrieve accounts, List accounts, Add Accounts, Update Account content
						#Update account properties, Intiate CPM Account management, Specify next account content,
						#Rename Accounts, Delete Accounts, View Audit Log, view safe members, access safe without confirmation,
						#create folders, delete folders, move accounts/folders
						
						#Adding the CPM as a User
						Add-PVSafeOwner -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Owner "passwordmanager" -Retrieve -Store -Delete -Administer -accessNoConfirmation -validateSafeContent -List -updateObjectProperties -usePassword -initiateCPMChange -initiateCPMChangeWithManualPassword -createFolder -deleteFolder -moveFrom -moveInto -viewAudit -viewPermissions -createObject -renameObject > $Null
						
						#Adding PPA Safe Admin as a User
						Add-PVSafeOwner -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Owner "PPA Safe Admin" -Retrieve -Store -Delete -Administer -accessNoConfirmation -validateSafeContent -List -updateObjectProperties -usePassword -initiateCPMChange -initiateCPMChangeWithManualPassword -createFolder -deleteFolder -moveFrom -moveInto -viewAudit -viewPermissions -createObject -renameObject -supervise -backup -manageOwners -eventsList -addEvents -unlockObject > $Null
                        
                        #May need to add what groups that you use to help manage users
						#Adding Support Group as a User
						#Add-PVSafeOwner -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Owner "Support Group" -List -initiateCPMChange > $Null
						
						#Adding Admins as a User
						#Add-PVSafeOwner -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Owner "Admins" -Retrieve -Store -Delete -Administer -accessNoConfirmation -validateSafeContent -List -updateObjectProperties -usePassword -initiateCPMChange -initiateCPMChangeWithManualPassword -createFolder -deleteFolder -moveFrom -moveInto -viewAudit -viewPermissions -createObject -renameObject -supervise -manageOwners -eventsList -addEvents -unlockObject > $Null
						
						#Adding OPs as a User
						#Add-PVSafeOwner -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Owner "Ops" -Retrieve -Store -Delete -Administer -accessNoConfirmation -validateSafeContent -List -usePassword -initiateCPMChange -moveFrom -moveInto -viewAudit -viewPermissions > $Null
						
						#Adding SysOps as a User
						#Add-PVSafeOwner -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Owner "SysOps" -Retrieve -Store -Delete -Administer -validateSafeContent -List -updateObjectProperties -usePassword -initiateCPMChange -createFolder -deleteFolder -moveFrom -moveInto -viewAudit -viewPermissions -createObject -renameObject -manageOwners -eventsList -addEvents -unlockObject > $Null
						
						#Adding the User as a User
						Add-PVSafeOwner -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Owner $($NewAccount.StandardID) -Retrieve -List -usePassword -viewAudit -viewPermissions > $Null
						
						#Adding the PVWA Gateway Accounts as a User
						Add-PVSafeGWAccount -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -gwAccount "PVWAGWAccounts" > $Null

						Close-PVSafe -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe > $Null
						$NewSafeCreated = $TRUE
						
					}
					$IsSafeOpen = ""
					$IsSafeOpen = Open-PVSafe -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe

					#Vault new account
					# Expected filename, Domain-HeightenedID
					if ($IsSafeOpen) {
						$AccountFileName = "$($NewAccount.Domain)-$($NewAccount.Account)"
						$FakePassword = ConvertTo-SecureString("Cyb3r@rk123!") -AsPlainText -Force
						Add-PVPasswordObject -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Folder $Folder -File $AccountFileName -Password $FakePassword > $Null
						Add-PVFileCategory -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Folder $Folder -File $AccountFileName -Category StandardID -Value $($NewAccount.StandardID) > $Null
						Add-PVFileCategory -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Folder $Folder -File $AccountFileName -Category EmployeeName -Value "$($ADuser.Surname), $($ADuser.GivenName)" > $Null
						Add-PVFileCategory -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Folder $Folder -File $AccountFileName -Category Address -Value $($NewAccount.FQDN) > $Null
						Add-PVFileCategory -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Folder $Folder -File $AccountFileName -Category UserName -Value $($NewAccount.Account) > $Null
						Add-PVFileCategory -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Folder $Folder -File $AccountFileName -Category LogonDomain -Value $($NewAccount.NetBios) > $Null
						Add-PVFileCategory -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Folder $Folder -File $AccountFileName -Category DeviceType -Value "Operating System" > $Null
						Add-PVFileCategory -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Folder $Folder -File $AccountFileName -Category PolicyID -Value $($NewAccount.PlatformID) > $Null
						#Resets the Password
						Add-PVFileCategory -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Folder $Folder -File $AccountFileName -Category ResetImmediately -Value "ReconcileTask" > $Null
						
						#Find new user that was just created
						$FindAccount = ""
						$FindAccount = Find-PVFile -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe -Folder $Folder -FilePattern $AccountFileName
						
						Close-PVSafe -Vault $Vault -SessionID $PACLiSessionID -User $PACLIUser -Safe $UserSafe  > $Null
					}
					else {
						Write-Output "Could not open safe: $UserSafe"
						$AccountVaulted = $FALSE
					}
					if ($FindAccount) {
						#If account found, email the user
						$AccountVaulted = $TRUE
						$Subject = "CyberArk - Heightened Account Vaulted"
						
						$Message = "Hello $($ADuser.GivenName),<br/><br/>Your account, $($NewAccount.Account), for $($NewAccount.DomainName) domain has been vaulted. To access your elevated credentials, please visit: $CyberArkURL.<br/>"
						$Message += "To use your access you will need to follow the steps in our <a href=""https://LinkToTrainingVideo"">training video</a>, "
						$Message += "our <a href=""https://LinkToTrainingGuides"">training guide</a>, or "
						$Message += "our <a href=""https://LinkToFAQ"">FAQ</a> which are "
						$Message += "available from <a href=""https://LinkToPortal"">Portal</a>.<br/><br/>"
						$Message += "If you do not have an RSA token, please request one using the form, "
						$Message += "<a href=""https://linktorequestRSAToken"">"
						$Message += "New VPN Access/Modify VPN Access/Replace Token.</a><br/><br/>"
						$Message += "<font style = ""background-color: yellow"">Once logged into CyberArk, select the magnifying glass at the top right of the page, to perform a blank search. This will return all of the accounts you are entitled to use.</font><br/><br/>"
						$Message += "Thanks,<br/><br/>The CyberArk Team"

						$ToEmail = ""
						$ToEmail = "$($NewAccount.StandardID)@$($EmailDomain)"
                        
                        if($BCC){
						$BCC = $To
                            . Email -ToEmail $ToEmail -BCC $BCC -Subject $Subject -Message $Message -CustomerEmail
                        }
                        else {
                            . Email -ToEmail $ToEmail -Subject $Subject -Message $Message -CustomerEmail
                        }
						
						$AccountsVaultedStatus += [pscustomobject]@{
							Domain         = $($NewAccount.FQDN)
							StandardID     = $($NewAccount.StandardID)
							HeightenedID   = $($NewAccount.Account)
							NewSafe        = $NewSafeCreated
							Safe           = $UserSafe
							AccountVaulted = $AccountVaulted
							FileName       = $AccountFileName
							LogonDomain    = $($NewAccount.NetBios)
							Notes          = ""
							DateVaulted    = $(get-date -f ddMMMyyyy)
						}	
					}
					else {
						$AccountsVaultedStatus += [pscustomobject]@{
							Domain         = $($NewAccount.FQDN)
							StandardID     = $($NewAccount.StandardID)
							HeightenedID   = $($NewAccount.Account)
							NewSafe        = $NewSafeCreated
							Safe           = $UserSafe
							AccountVaulted = $AccountVaulted
							FileName       = $AccountFileName
							LogonDomain    = $($NewAccount.NetBios)
							Notes          = ""
							DateVaulted    = $(get-date -f ddMMMyyyy)
						}
						$IssuesFound = $True
					}
				}
			}
			Disconnect-PVVault -vault $Vault -SessionID $PACLiSessionID -user $PACLIUser > $Null
			Stop-PVPacli > $Null
			$PACLIConnection = ""
			
			$EndTime = Get-Date
			$TotalTime = $EndTime - $StartTime
			Write-Output "Total run time: $TotalTime"
			
			#Email status report of vaulted accounts
			if ($AccountsVaultedStatus) {
				if ($IssuesFound) {
					$Subject = "Accounts Automatically Vaulted-$(get-date -f ddMMMyyyy): Issues Found"
				}
				else {
					$Subject = "Accounts Automatically Vaulted-$(get-date -f ddMMMyyyy)"
				}
				$Message = "Hello Team,<br/><br/>Here is a list of all the accounts that have been automatically vaulted.<br/><br/>"
				$Message += "<br/><br/><br/>Total Script Run Time: $($TotalTime.Minutes) minute(s)"
				. ExportVariable $AccountsVaultedStatus "AccountsVaultedStatus"
				. Email -ToEmail $To -Subject $Subject -Message $Message -File $File
				
				if (Test-Path "$myResults\Master\AccountsVaultedMaster-$(get-date -f yyyy).csv") {
					$AccountsVaultedStatus | Where-Object {$_.AccountVaulted -eq $True} | export-csv $myResults\Master\AccountsVaultedMaster-$(get-date -f yyyy).csv -noType -Append
				}
				else {
					$AccountsVaultedStatus | Where-Object {$_.AccountVaulted -eq $True} | export-csv $myResults\Master\AccountsVaultedMaster-$(get-date -f yyyy).csv -noType
				}
			}
		}
		else{
			$Subject = "CyberArk Vaulting Issue: Too Many Accounts to be vaulted, verify and then override"
			$Message = "There are too many accounts to be process.  Please confirm that they are valid.  If they are valid, set CyberArkCountOverride = $True."
			#$To = "someone@company.com"
			. ExportVariable $NotVaulted "AccountsNotVaulted"
			. Email -ToEmail $To -Subject $Subject -Message $Message -File $File
		}
    }
    else {
        Write-Output "Issue logging into PACLI"
    }
}
else {
    $Subject = "CyberArk Vaulting Issue: Error Getting Heightened IDs From CyberArk"
    $Message = "Received the following error during execution: <br/>$CyberArkErrorDetails"
    . Send-Error $Subject $Message
}
