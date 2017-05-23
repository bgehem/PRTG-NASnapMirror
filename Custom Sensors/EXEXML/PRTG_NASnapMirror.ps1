# Powershell PRTG Custom EXEXML sensor for discovery and monitoring of snapmirror
# relationships on a NetApp cDOT source without credentials for the destination
#
Param(
     [Parameter(Mandatory=$true)]
     [String]$Username,
     [Parameter(Mandatory=$true)]
     [String]$Password,
     [Parameter(Mandatory=$true)]
     [String]$Controller,
     [switch]$Discover,
     [String]$SourceVServer,
     [String]$SourceVolume,
     [String]$DestinationVServer,
     [String]$DestinationVolume
   )
Try{
# Disable certificate check
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    # Current Scriptname    
    $ScriptName = $MyInvocation.MyCommand.Name 

    # Convert password parameter to PSCredential
    $SecPassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $Cred = New-Object PSCredential($Username,$SecPassword)
    
    # Ontapi uri  
    $Uri = "https://{0}/servlets/netapp.servlets.admin.XMLrequest_filer" -f $Controller

    if($Discover){
        # Autodiscover snapmirror relations
        # https://kb.paessler.com/en/topic/68109-how-can-i-use-meta-scans-for-custom-exe-script-sensors

        # Get snapmirror destinations
        $Body = '<netapp version="1.7" xmlns="http://www.netapp.com/filer/admin"><snapmirror-get-destination-iter><query></query><max-records>250</max-records></snapmirror-get-destination-iter></netapp>'
        
        $Response = Invoke-WebRequest -UseBasicParsing -Credential $Cred -Uri $Uri -Method POST -Body $Body
        
        $XmlResponse = [xml]$Response.Content
        
        if($XmlResponse.netapp.results.status -ne "passed"){
            throw $XmlResponse.netapp.results.reason
        }
        
        $SnapMirrorDests = $XmlResponse.netapp.results.'attributes-list'.ChildNodes
        
        # Build Output discovery results
        $Out = "<prtg>"
        foreach($SnapMirrorDest in $SnapMirrorDests){
            $SMSourceLocation = $SnapMirrorDest.'source-location'
            $SMSourceVServer = $SnapMirrorDest.'source-vserver'
            $SMSourceVolume = $SnapMirrorDest.'source-volume'

            $SMDestinationlocation = $SnapMirrorDest.'destination-location'
            $SMDestinationVServer = $SnapMirrorDest.'destination-vserver'
            $SMDestinationVolume = $SnapMirrorDest.'destination-volume'
    
            $Out += "<item>"
            $Out +=   "<name>Dataprotection: {0}->{1}</name>" -f $SMSourceLocation, $SMDestinationlocation 
            $Out +=   "<exefile>{0}</exefile>" -f $ScriptName
            $Out +=   "<params> -Username %linuxuser -Password %linuxpassword -Controller %host -SourceVServer {0} -SourceVolume {1} -DestinationVServer {2} -DestinationVolume {3}</params>" -f $SMSourceVServer, $SMSourceVolume, $SMDestinationVServer, $SMDestinationVolume
            $Out += "</item>"
        }
        $Out += "</prtg>"
        # Output results
        $Out

    }else{
        # Monitor snapmirror relationship
        $Body = '<netapp vfiler="{0}" target-vserver-name="{2}" version="1.7" xmlns="http://www.netapp.com/filer/admin"><snapmirror-get-iter><query><snapmirror-info><source-vserver>{0}</source-vserver><source-volume>{1}</source-volume><destination-vserver>{2}</destination-vserver><destination-volume>{3}</destination-volume></snapmirror-info></query><max-records>250</max-records></snapmirror-get-iter></netapp>' -f $SourceVServer, $SourceVolume, $DestinationVServer, $DestinationVolume
                
        $Response = Invoke-WebRequest -UseBasicParsing -Credential $Cred -Uri $Uri -Method POST -Body $Body
        
        $XmlResponse = [xml]$Response.Content
        
        if($XmlResponse.netapp.results.status -ne "passed"){
            throw $XmlResponse.netapp.results.reason
        }
        
        $SnapMirrorInfo = $XmlResponse.netapp.results.'attributes-list'.ChildNodes
        
        $IsHeathy = 0       
        If($SnapMirrorInfo[0].'is-healthy' -eq "true"){
            $IsHeathy = 1       
        }

        # Build Output
        $Out =  "<prtg>"
        $Out +=     "<result>"
        $Out +=         "<channel>Lag</channel>"
        $Out +=         "<value>{0}</value>" -f $SnapMirrorInfo[0].'lag-time'
        $Out +=         "<unit>TimeSeconds</unit>"
        $Out +=        "<LimitMode>1</LimitMode>"
        $Out +=        "<LimitMaxWarning>90000</LimitMaxWarning>"
        $Out +=        "<LimitMaxError>180000</LimitMaxError>"
        $Out +=    "</result>"
        $Out +=    "<result>"
        $Out +=        "<channel>Is Healthy</channel>"
        $Out +=        "<value>{0}</value>" -f $IsHeathy
        $Out +=        "<LimitMode>1</LimitMode>"
        $Out +=        "<LimitMinError>1</LimitMinError>"
        $Out +=        "<ShowChart>0</ShowChart>"
        $Out +=        "<CustomUnit></CustomUnit>"
        $Out +=        "<ValueLookup>prtg.customlookups.netapp.smhealth</ValueLookup>"
        $Out +=    "</result>"
        $Out +=    "<result>"
        $Out +=        "<channel>Last transfer duration</channel>"
        $Out +=        "<value>{0}</value>" -f $SnapMirrorInfo[0].'last-transfer-duration'
        $Out +=        "<unit>TimeSeconds</unit>"
        $Out +=    "</result>"
        $Out +=    "<result>"
        $Out +=        "<channel>Last transfer size</channel>"
        $Out +=        "<value>{0}</value>" -f $SnapMirrorInfo[0].'last-transfer-size'
        $Out +=        "<unit>BytesDisk</unit>"
        $Out +=    "</result>"
        $Out += "</prtg>"

        # Output results
        $Out
    }
}Catch{
    "<prtg><error>1</error><text>{0}</text></prtg>" -f $_.Exception.Message
}
