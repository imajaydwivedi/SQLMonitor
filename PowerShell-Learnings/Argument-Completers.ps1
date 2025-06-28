# https://www.youtube.com/watch?v=bRGb0ffGNjM


# Validate set based method. DOES NOT allow other values
function Get-Color {
    [CmdletBinding()]
    Param (
        [ValidateSet('green','red','blue')]
        [String]$Color
    )

    return $Color
}

enum veggies {
    carrot
    potato
    tomato
}

# Enum based argument completor return the values of the enum. No other values are allowed
  # DOES NOT allow other values
function Get-Vegetable {
    [CmdletBinding()]
    param (
        [veggies]$Vegetable
    )

    return $Vegetable

}

# ArgumentCompleter attribute. Allows other values in argument
    # Takes scriptblock
function Get-City {
    [CmdletBinding()]
    param (
        [ArgumentCompleter({'Hyderabad','Rewa','Bangalore'})]
        [String]$City
    )
    begin {}
    process {
        return $City
    }
    end {}
}


# Has Icon. No ScriptBlock. Respects user input in console
    # Takes array
function Get-Pizza {
    [CmdletBinding()]
    param (
        [ArgumentCompletions('Hawaiian', 'Pepperoni', 'PannerToppings')]
        [String]$Type
    )
    begin {}
    process {
        return $Type
    }
    end {}
}


# Dynamic argument completions
function Get-MyService {
    [CmdletBinding()]
    Param (
        [ArgumentCompleter({ Get-Service | Select-Object -ExpandProperty Name})]
        [String]$ServiceName
    )
    begin {}
    process {
        return $ServiceName
    }
    end {}
}



# Dynamic argument completions with other features
function Get-MyProcess {
    [CmdletBinding()]
    Param (
        [ArgumentCompleter({
            $processNames = Get-Process | Select-Object -ExpandProperty Name
            $processNames | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_ + " itemText", 'ParameterValue', $_ + ' ToolTipText')
            }
        })]
        [String]$ProcessName
    )
    begin {}
    process {
        return $ProcessName
    }
    end {}
}

Get-MyProcess -ProcessName 

