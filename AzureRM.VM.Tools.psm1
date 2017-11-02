
# region dynamic location parameter function 
Function DynamicLocationParam {
    <#
     .SYNOPSIS
     Function to add location description
     
     .DESCRIPTION
     This command uses the azure 'Get-AzureRmLocation' cmdlet to obtain locations in azure.
     A lot of the commands currently don't dynamically generate the locations used, making it
     an extra task to find.
     
     .EXAMPLE
     This is added as a dynamic parameter to a function
     
     .NOTES
     General notes
     #>

    # Set the dynamic parameters' name
    $ParameterName = 'Location'

    # Create the dictionary 
    $RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

    # Create the collection of attributes
    $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]

    # Create and set the parameters' attributes
    $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
    $ParameterAttribute.Mandatory = $true
    $ParameterAttribute.Position = 1

    # Add the attributes to the attributes collection
    $AttributeCollection.Add($ParameterAttribute)

    # Generate and set the ValidateSet 
    $LocationAtr = Get-AzureRmLocation | Select-Object -expand Location
    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute($LocationAtr)

    # Add the ValidateSet to the attributes collection
    $AttributeCollection.Add($ValidateSetAttribute)

    # Create and return the dynamic parameter
    $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName, [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($ParameterName, $RuntimeParameter)
    return $RuntimeParameterDictionary
}
# end region 

# region helper functions
Function Connect-AZRm {
    <#
    .SYNOPSIS
    Connect to Azure Resoure Manager
    
    .DESCRIPTION
    Connect to Azure through PowerShell
    
    .PARAMETER Credentials
    Pass Azure credentials
    
    .PARAMETER TenantId
    Azure Tenant Id
    
    .EXAMPLE
    Connect-AZRm -Credentials User@Domain.com -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
    
    .NOTES
    General notes
    #>
    [CmdletBinding()]
    param (
        [System.Management.Automation.PSCredential] $Credentials,
        [string] $TenantId
    )
    
    $connect = @{
        Credential  = $Credentials
        TenantId    = $TenantId
        Environment = 'AzureCloud'
        ErrorAction = 'Stop'
    }
    # Make connection
    Try { 
        Login-AzureRmAccount @connect 
        Write-Host -ForegroundColor Cyan "Connection Successful to Azure"
    } Catch { 
        $pscmdlet.ThrowTerminatingError($_)
    }
}

Function Get-AZrMVmOptionSizes {
    <#
     .SYNOPSIS
     List VM size options by location
     
     .DESCRIPTION
     A helper function to list Virtual Machines sizes available by location.
     
     .EXAMPLE
     Get-AZrMVmOptionSizes -Location 'UkSouth'
     
     .NOTES
     Uses the dynamic location parameter to easily search through locations
     #>

    [CmdletBinding()]
    Param()
 
    DynamicParam {
        DynamicLocationParam
    }

    begin {
        # Bind the parameter to a friendly variable
        $Location = $PsBoundParameters['Location']
    }

    Process {
        # Set properties to view
        $outputInfo = 'Name', 'NumberOfCores', 'MemoryInMB', 'MaxDataDiskCount' 

        # Show VM size options for $Location
        Get-AzureRmVmSize -Location $Location | 
            Sort-Object Name | 
            Select-Object $outputInfo 
    }
}
Function Get-AZrMPublisher {
    <#
     .SYNOPSIS
     Find image publisher 
     
     .DESCRIPTION
     The function takes a wildcard search on the publisher name
     making is easier to find a image publisher. The image publisher
     determines what images are available to use.
     
     .PARAMETER Publisher
     Take a wildcard search on publisher. i.e. MicrosoftWindows*,
     *Windows*
     
     .EXAMPLE
     Get-AZrMPublisher -Publisher MicrosoftWindows* -Location uksouth

     PublisherName                 Location
     -------------                 --------
     MicrosoftWindowsDesktop       uksouth
     MicrosoftWindowsServer        uksouth
     MicrosoftWindowsServerHPCPack uksouth
     
     .NOTES
     The location parameter uses the dynamic parameter, 'DynamicLocationParam'.
     #>

    [CmdletBinding()]
    Param(
        [string] $Publisher
    )
 
    DynamicParam {
        DynamicLocationParam
    }

    begin {
        # Bind the parameter to a friendly variable
        $Location = $PsBoundParameters['Location']
    }

    Process {
        # Set properties to view
        $outputinfo = 'Publishername', 'location'

        # Find publishers
        Get-AzureRmVMImagePublisher -Location $location | 
            Where-Object {$_.PublisherName -like "*$Publisher*"} |
            Sort-Object PublisherName |
            select-Object $outputinfo
    }
} 

Function New-AZRmRG {
    <#
     .SYNOPSIS
     Create a resource group in Azure
     
     .DESCRIPTION
     A helper function to create a resource group in azure utlising 
     the dynamic location parameter
     
     .PARAMETER ResourceGroupName
     Takes a string with the name of the resource group you wish to create.
     
     .EXAMPLE
     New-AZRmRG -ResourceGroupName 'Test' -Location westeurope
     
     .NOTES
     The location parameter uses the dynamic parameter, 'DynamicLocationParam'.
     #>

    [CmdletBinding()]
    Param(
        [string]$ResourceGroupName
    )
 
    DynamicParam {
        DynamicLocationParam
    }

    begin {
        # Bind the parameter to a friendly variable
        $Location = $PsBoundParameters['Location']
    }
    process {
        if (-not (Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorAction 'SilentlyContinue')) {
            $params = @{
                Name        = $ResourceGroupName
                Location    = $Location
                ErrorAction = 'stop'
            }
            Try {
                $null = New-AzureRmResourceGroup @params
                Write-Verbose -Message "[PROCESS] Created Resource Group '$ResourceGroupName' successfully"
            } Catch {
                Write-Error -Message "Failed to create group"
            }
        } else {
            Write-Verbose -Message "[PROCESS] Resource Group '$ResourceGroupName' already exists"
        }    
    }
} 
Function New-AZRmStorageAccount {
    <#
     .SYNOPSIS
     Create a storage account in Azure
     
     .DESCRIPTION
     Create a storage account to attach a newly created virtual
     machine to.
     
     .PARAMETER ResourceGroupName
     Parse an existing resource group for the storage account to 
     be created in.
     
     .PARAMETER StorageName
     Name your storage account
     
     .PARAMETER StorageType
     Define the type of storage required for the virtual machine
     
     .EXAMPLE
     New-AZRmStorageAccount -ResourceGroupName 'Test' -StorageName 'StorageAcc1' -StorageType Standard_GRS -Location uksouth
     
     .NOTES
     The location parameter uses the dynamic parameter, 'DynamicLocationParam'.
     #>

    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [string] $ResourceGroupName,
        [string] $StorageName,
        [ValidateSet('Premium_LRS', 'Standard_GRS', 'Standard_LRS', 'Standard_RAGRS', 'Standard_ZRS')]
        [string] $StorageType
    )
    
    DynamicParam {
        DynamicLocationParam    
    }

    Begin {
        # Bind the parameter to a friendly variable
        $Location = $PsBoundParameters['Location']
    }
 
    Process {
        # Check if group exists if not, create
        New-AZRmRG -ResourceGroupName $ResourceGroupName -Location $Location

        $sa = @{
            ResourceGroupName = $ResourceGroupName
            Name              = $StorageName
            Type              = $StorageType
            Location          = $Location
            ErrorAction       = 'Stop'
        }

        Try {
            $null = New-AzureRmStorageAccount @sa
            Write-verbose -Message "[PROCESS] Created Storage account"
        } Catch {
            $pscmdlet.ThrowTerminatingError($_)            
        }
    }
}
# end region helper functions

# region ArgumentCompleter
# Add location completion to 'New-AzureRmStorageAccount' 
Register-ArgumentCompleter -CommandName New-AzureRmStorageAccount -ParameterName Location -ScriptBlock {
    Get-AzureRmLocation | Select-Object -ExpandProperty Location    
}

Register-ArgumentCompleter -CommandName Get-AzureRmVMImageOffer -ParameterName Publishername -ScriptBlock {
    Get-AzureRmPublisher -Publisher * -location $_.location
}
# region end ArgumentCompleter 

# region main functions
# Configure Network
Function New-AZRmNetwork {
    <#
     .SYNOPSIS
     Create a network for a Virtual machine
     
     .DESCRIPTION
     Create and define a network to use with a virtual machine.
     
     .PARAMETER ResourceGroupName
     Parse an existing resource group for the storage account to 
     be created in.
     
     .PARAMETER NetInterfaceName
     Add a name for the network interface
     
     .PARAMETER AllocationMethod
     takes two options, either a 'Dynamic' or 'Static' IP.
     
     .PARAMETER VNetName
     Add a name for the Vnet adapter
     
     .PARAMETER SubnetName
     Add a name for the Subnet
     
     .PARAMETER VNetSubnetAddressPrefix
     IP range for the subnet, i.e. '10.0.0.0/24'
     
     .PARAMETER VNetAddressPrefix
     Address range
     
     .EXAMPLE
     New-AZRmNetwork -ResourceGroupName 'test' -NetInterfaceName 'Network01' -AllocationMethod Static -VNetName 'Vnet09' -SubnetName 'Subnet01' `
     -VNetSubnetAddressPrefix '10.0.0.0/24' -VNetAddressPrefix '10.0.0.0/16' -Location uksouth
     
     .NOTES
     The location parameter uses the dynamic parameter, 'DynamicLocationParam'.
     #>
    [CmdletBinding()]
    param(
        [string] $ResourceGroupName,
        [string] $NetInterfaceName,
        [ValidateSet('Dynamic', 'Static')] $AllocationMethod,
        [string] $VNetName = "VNet01",
        [string] $SubnetName,
        [string] $VNetSubnetAddressPrefix = "10.0.0.0/24",
        [string] $VNetAddressPrefix = "10.0.0.0/16"
    )
    
    DynamicParam {
        DynamicLocationParam    
    }
    End {
        # Bind the parameter to a friendly variable
        $Location = $PsBoundParameters['Location']

        # Suppress Azure cmdlet message,
        # 'WARNING: The output object type of this cmdlet will be modified in a future release.' 
        $WarningPreference = 'SilentlyContinue' 

        # Check if group exists if not, create
        New-AZRmRG -ResourceGroupName $ResourceGroupName -Location $Location
        
        # Create Public IP Address
        $PIP = @{
            Name              = "${NetInterfaceName}_nic1"
            ResourceGroupName = $ResourceGroupName 
            Location          = $Location 
            AllocationMethod  = $AllocationMethod
            ErrorAction       = 'Stop'
        }
        Try {
            $PublicIP = New-AzureRmPublicIpAddress @PIP
            Write-Verbose -Message "[PROCESS] Created Public IP Address"
            
            # Remote Desktop Rule
            $RDPrule = [Microsoft.Azure.Commands.Network.Models.PSSecurityRule]@{
                Name                     = 'RDP-Rule'
                Description              = "Allow RDP"
                Access                   = 'Allow' 
                Protocol                 = 'Tcp' 
                Direction                = 'Inbound' 
                Priority                 = 1000 
                SourceAddressPrefix      = [System.Collections.Generic.List[string]]'*'
                SourcePortRange          = [System.Collections.Generic.List[String]]'*' 
                DestinationAddressPrefix = [System.Collections.Generic.List[String]]'*' 
                DestinationPortRange     = [System.Collections.Generic.List[String]]'3389'
            }

            # Web Traffic Rule
            $WebRule = [Microsoft.Azure.Commands.Network.Models.PSSecurityRule]@{
                Name                     = 'Web-Traffic-Rule'
                Description              = "Allow Web Traffic"
                Access                   = 'Allow'
                Protocol                 = 'Tcp' 
                Direction                = 'Inbound' 
                Priority                 = 1001 
                SourceAddressPrefix      = [System.Collections.Generic.List[string]]'*'
                SourcePortRange          = [System.Collections.Generic.List[String]]'*' 
                DestinationAddressPrefix = [System.Collections.Generic.List[String]]'*' 
                DestinationPortRange     = [System.Collections.Generic.List[String]]'80'
            }

            Write-Verbose -Message "[PROCESS] Remote Desktop and Web Traffic Rule Defined"

            # Security Group 
            $SecurityGrp = @{
                ResourceGroupName = $ResourceGroupName
                Location          = $Location
                Name              = "${NetInterfaceName}_Security_grp"
                SecurityRules     = $RDPrule, $WebRule
                ErrorAction       = 'Stop'
            }
            $NetSecGrp = New-AzureRmNetworkSecurityGroup @SecurityGrp
            Write-Verbose -Message "[PROCESS] Security Group Successfully Created"
            
            # Configure Subnet
            $Subnet = @{
                Name                 = $SubnetName 
                AddressPrefix        = $VNetSubnetAddressPrefix
                NetworkSecurityGroup = $NetSecGrp
                ErrorAction          = 'Stop'
            }
            $SubnetCFG = New-AzureRmVirtualNetworkSubnetConfig @Subnet
            Write-Verbose -Message "[PROCESS] Configured Subnet Successfully"

            # Configure VirtualNetwork 
            $VNet = @{ 
                Name              = $VNetName 
                ResourceGroupName = $ResourceGroupName 
                Location          = $Location 
                AddressPrefix     = $VNetAddressPrefix 
                Subnet            = $SubnetCFG
                ErrorAction       = 'Stop'
            }
            $VirtualNet = New-AzureRmVirtualNetwork @VNet
            Write-Verbose -Message "[PROCESS] Configured Virtual Network Successfully"    

            # Configure Network Interface
            $InterFace = @{
                Name              = $NetInterfaceName 
                ResourceGroupName = $ResourceGroupName 
                Location          = $Location 
                SubnetId          = $VirtualNet.Subnets[0].Id 
                PublicIpAddressId = $PublicIP.Id
                ErrorAction       = 'Stop'
            }
            $Null = New-AzureRmNetworkInterface @InterFace
            Write-Verbose -Message "[PROCESS] Configured Virtual Interface Successfully"  

        } catch {
            $pscmdlet.ThrowTerminatingError($_)
        }
    }
}

# Create Virtual Machine
Function New-AZRmVirtualMachine {
    <#
     .SYNOPSIS
     Create the Virtual Machine
     
     .DESCRIPTION
     The function will fully provision the virtual machine
     ready for use.
     
     .PARAMETER Credentials
     Parse the credentials that the virtual machine will use
     for login
     
     .PARAMETER ResourceGroupName
     Parse an existing resource group for the storage account to 
     be created in.
     
     .PARAMETER VirtualMachineName
     Name the virtual machine
     
     .PARAMETER VMSizeOption
     Add the virtual machine size to use. Use helper
     function 'Get-AZrMVmOptionSizes' to help find
     virtual machine sizing options i.e. 'Standard_A2'
     
     .PARAMETER OSPlatform
     Choose between either 'Linux' or 'Windows' for operating
     system platform.
     
     .PARAMETER ComputerName
     Add a computer name
     
     .PARAMETER PublisherName
     Set a publisher name. Use helper function 'Get-AZrMPublisher'
     to get options available.
     
     .PARAMETER Offer
     Set what type of Operating System to build, i.e. 'WindowsServer'
     
     .PARAMETER Skus
     Choose the Operating System to build the Virtual machine as.
     i.e. '2012-R2-Datacenter'
     
     .PARAMETER Version
     Choose the version. This parameter is set to 'latest' as default.
     
     .PARAMETER NetInterfaceName
     Add the network interface name to use
     
     .PARAMETER StorageName
     Name your storage account
     
     .PARAMETER StorageType
     Define the type of storage required for the virtual machine
     
     .PARAMETER CreateOption
     Specifies whether this cmdlet creates a disk in the virtual machine from a platform 
     or user image, or attaches an existing disk. Options are 'FromImage' or 'Attach'.
     
     .PARAMETER ProvisionVMAgent
     ndicates that the settings require that the virtual machine agent be installed on 
     the virtual machine.
     
     .PARAMETER EnableAutoUpdate
     Indicates that this cmdlet enables auto update.
     
     .EXAMPLE
     $DefineVmParams = @{
        Credentials        = $psCred
        ResourceGroupName  = 'VM'
        VirtualMachineName = 'DemoExampleVM'
        VMSizeOption       = 'Standard_A2'
        OSPlatform         = 'Windows'
        ComputerName       = 'Computer1'
        Location           = 'WestEurope'
        PublisherName      = 'MicrosoftWindowsServer'
        Offer              = 'WindowsServer'
        Skus               = '2012-R2-Datacenter'
        NetInterfaceName   = 'ServerNet'
        StorageName        = 'vmstorageunit12'
        StorageType        = 'Standard_GRS'
        ProvisionVMAgent   = $true
        EnableAutoUpdate   = $true
        Verbose            = $true
     }
     New-AZRmVirtualMachine @DefineVmParams
     
     .NOTES
     The location parameter uses the dynamic parameter, 'DynamicLocationParam'.
     #>
    [CmdletBinding()]
    param (
        # Pass in Username and password of Admin Account
        [Alias("Cred")]
        [System.Management.Automation.PSCredential]
        $Credentials,
        [string] $ResourceGroupName,
        [String] $VirtualMachineName,
        [String] $VMSizeOption,
        [ValidateSet('Windows', 'Linux')] 
        [string] $OSPlatform,
        [String] $ComputerName,
        [String] $PublisherName,
        [string] $Offer,
        [string] $Skus,
        [String] $Version = 'latest',
        [string] $NetInterfaceName,
        [string] $StorageName,
        [ValidateSet('Premium_LRS', 'Standard_GRS', 'Standard_LRS', 'Standard_RAGRS', 'Standard_ZRS')]
        [string] $StorageType,
        [ValidateSet('Attach', 'FromImage', 'Empty')]
        [string] $CreateOption = 'FromImage',
        [Switch] $ProvisionVMAgent, 
        [Switch] $EnableAutoUpdate
    )
    DynamicParam {
        DynamicLocationParam
    }

    Begin {
        # Bind the parameter to a friendly variable
        $Location = $PsBoundParameters['Location']
        
        ## pre script validation checks
        # Find VM size variable in Azure
        $VMSize = Get-AZrMVmOptionSizes -Location $Location | 
            Where-Object {$_.Name -contains $VMSizeOption}
        
        # if invalid option terminate    
        if (-not $VMSize) {Write-Error -Exception "Not a valid Value: $VMSizeOption" -ErrorAction Stop}

        # Check for publisher
        $Publisher = Get-AZrMPublisher -Publisher * -Location $location |
            Where-Object {$_.PublisherName -contains $PublisherName}

        # if invalid option terminate  
        if (-not $Publisher) {Write-Error -Exception "Not a valid Value: $PublisherName" -ErrorAction Stop}   
    }

    Process {
        # Check if group exists if not, create
        New-AZRmRG -ResourceGroupName $ResourceGroupName -Location $Location
                
        # Creates a configurable virtual machine object
        $vm = @{
            VMName      = $VirtualMachineName 
            VMSize      = $VMSize.Name
            ErrorAction = 'stop'
        }
        Try {
            $VmObject = New-AzureRmVMConfig @vm
            Write-Verbose -Message "[PROCESS] Created Virtual Machine Object"

            # Set VM Operating system
            $os = @{ 
                ComputerName     = $ComputerName 
                Credential       = $Credentials 
                $OSPlatform      = $true
                ProvisionVMAgent = $ProvisionVMAgent.ToBool()
                EnableAutoUpdate = $EnableAutoUpdate.ToBool()
                ErrorAction      = 'Stop'
            }
            # Sets operating system properties for a virtual machine
            $Null = $VmObject | Set-AzureRmVMOperatingSystem @os
            Write-Verbose -Message "[PROCESS] Set OS properties for VM"

            # Specifies the image for a virtual machine.
            $SourceImage = @{
                VM            = $VmObject
                PublisherName = $PublisherName
                Offer         = $Offer
                Skus          = $Skus
                Version       = $version
                ErrorAction   = 'Stop'
            }

            $null = Set-AzureRmVMSourceImage @SourceImage
            Write-Verbose -Message "[PROCESS] Set image details for Virtual Machine" 

            # Create storage account 
            # Call helper function to create
            $Storage = @{
                ResourceGroupName = $ResourceGroupName
                StorageName       = $StorageName
                StorageType       = $StorageType
                Location          = $Location
                ErrorAction       = 'Stop'
            }
            
            $null = New-AZRmStorageAccount @Storage 
            $NewStorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageName 
            
            # Create OS Disk for Virtual Machine
            $OSDiskName = '{0}_{1}' -f $VirtualMachineName, 'OSDisk'
            # Set Disk Uri
            $OSDiskUri = '{0}{1}' -f $NewStorageAccount.PrimaryEndpoints.Blob.ToString(), "vhds/${OSDiskName}.vhd"
            # Create VM Disk
            $VMOSDisk = @{
                VM           = $VmObject
                Name         = $OSDiskName
                VhdUri       = $OSDiskUri
                Caching      = 'ReadWrite'
                CreateOption = $CreateOption 
                ErrorAction  = 'Stop'
            }

            $null = Set-AzureRmVMOSDisk @VMOSDisk
            Write-Verbose -Message "[PROCESS] Created OS Disk for Virtual Machine"

            # Adds a network interface to a virtual machine
            $Interface = Get-AzureRmNetworkInterface -ResourceGroupName $ResourceGroupName -Name $NetInterfaceName 
            $VmObject = Add-AzureRmVMNetworkInterface -VM $VmObject -Id $Interface.Id            
            
            Write-Verbose -Message "[PROCESS] Added network interface to VM"

            # Creates a virtual machine
            $NewVM = @{
                ResourceGroupName = $ResourceGroupName
                Location          = $Location
                VM                = $VmObject
                ErrorAction       = 'Stop'
            }
            $Null = New-AzureRmVM @NewVM
            Write-Verbose -Message "[PROCESS] Created Virtual Machine, process complete"
        } Catch {
            $pscmdlet.ThrowTerminatingError($_)
        }
    } # Process block
} # Function block

# Make RDP connection to Azure Virtual Machine
Filter Connect-AZRmRDP {
    [Cmdletbinding()]
    Param (
        [Parameter(Mandatory, Position = 0)]
        [string] $ResourceGroupName,
        [Parameter(Mandatory, ValueFromPipeline, Position = 1)]
        [String] $VirtualMachineName
    )
    
    # Set Virtual Machine search
    $Vm = @{
        ResourceGroupName = $ResourceGroupName 
        Name              = $VirtualMachineName
        ErrorAction       = 'Stop'
    }
    Try {
        # Find Virtual Machine
        $rdpVM = Get-AzureRmVM @Vm
        Write-Verbose -Message "[PROCESS] Virtual Machine details found"

        # Get NIC name
        $Id = @{ResourceGroupName = $ResourceGroupName; ErrorAction = 'Stop'}
        $Nic = Get-AzureRmNetworkInterface @Id | 
            Where-Object {$_.Id -Like ($rdpVM.NetworkProfile.NetworkInterfaces.id)}

        $Nic = ($Nic.IpConfigurations.PublicIpAddress.ID -split '/')[-1]

        Write-Verbose -Message "[PROCESS] NIC name found"
        # Public IP Address for RDP connection
        $Ip = @{
            Name              = $Nic
            ResourceGroupName = $rdpVM.ResourceGroupName
            ErrorAction       = 'Stop'
        }
        $PublicIp = (Get-AzureRmPublicIpAddress @Ip).IpAddress
        Write-Verbose -Message "[PROCESS] Public IP Address found "
            
        # RDP Connection  
        mstsc -v:$PublicIp /prompt
    } Catch {
        $pscmdlet.ThrowTerminatingError($_)
    }        
}
# end region main functions