## Dynamic Param location template
Function DynamicLocationParam {
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

# Helper Functions

# View VM size Options
Function Get-AZrMVmOptionSizes {
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

# Create a resource group
Function New-AZRmRG {
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
        $params = @{
            Name        = $ResourceGroupName
            Location    = $Location
            ErrorAction = 'stop'
        }
        Try {
            $null = New-AzureRmResourceGroup @params
            Write-Verbose -Message "Created $ResourceGroupName successfully"
        } Catch {
            Write-Error -Message "Failed to create group"
        }    
    }
}

# Add location completion to 'New-AzureRmStorageAccount' 
Register-ArgumentCompleter -CommandName New-AzureRmStorageAccount -ParameterName Location -ScriptBlock {
    Get-AzureRmLocation | Select-Object -ExpandProperty Location    
}

Register-ArgumentCompleter -CommandName Get-AzureRmVMImageOffer -ParameterName Publishername -ScriptBlock {
    Get-AzureRmPublisher -Publisher * -location $_.location
}

# Create new Storage Account
Function New-AZRmStorageAccount {
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

# Configure Network
Function New-AZRmNetwork {
    [CmdletBinding()]
    param(
        [string] $ResourceGroupName,
        [string] $InterfaceName,
        [ValidateSet('Dynamic', 'Static')] $AllocationMethod,
        [string] $VNetName = "VNet09",
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
                
        # Create Public IP Address
        $PIP = @{
            Name              = "${InterfaceName}_nic1"
            ResourceGroupName = $ResourceGroupName 
            Location          = $Location 
            AllocationMethod  = $AllocationMethod
            ErrorAction       = 'Stop'
        }
        Try {
            $PublicIP = New-AzureRmPublicIpAddress @PIP
            Write-Verbose -Message "[PROCESS] Created Public IP Address"

            # Configure Subnet
            $Subnet = @{
                Name          = $SubnetName 
                AddressPrefix = $VNetSubnetAddressPrefix
                ErrorAction   = 'Stop'
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
                Name              = $InterfaceName 
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
        [string] $InterfaceName,
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
            $Interface = Get-AzureRmNetworkInterface -ResourceGroupName $ResourceGroupName -Name $InterfaceName 
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
Function Connect-AZRmRDP {
    [Cmdletbinding()]
    Param (
        [Parameter(Mandatory, Position = 0)]
        [string] $ResourceGroupName,
        [Parameter(Mandatory, ValueFromPipeline, Position = 1)]
        [String] $VirtualMachineName
    )
    
    Process {
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
            
            # Create Scriptblock  
            $RDPcommand = [scriptblock]::Create("mstsc -v:$PublicIp /prompt")
            # Dot source Scriptblock
            .$RDPcommand
        } Catch {
            $pscmdlet.ThrowTerminatingError($_)
        }        
    }
}