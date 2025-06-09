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
