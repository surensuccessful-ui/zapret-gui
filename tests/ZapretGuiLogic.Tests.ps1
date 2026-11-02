. (Join-Path $PSScriptRoot '..\zapret-gui-logic.ps1')

Describe 'Compare-ZapretVersion' {
    It 'orders numeric versions' {
        Compare-ZapretVersion '1.0.30' '1.0.28' | Should Be 1
        Compare-ZapretVersion '1.0.28' '1.0.30' | Should Be -1
        Compare-ZapretVersion '1.0.28' '1.0.28' | Should Be 0
        Compare-ZapretVersion '1.10.0' '1.9.0' | Should Be 1
    }
}

Describe 'Select-GuiUpdateAsset' {
    It 'prefers the exact updater name' {
        $picked = Select-GuiUpdateAsset @(
            'ZapretGUI-1.0.28-win10-win11.exe',
            'SHA256SUMS.txt',
            'ZapretGUI.exe'
        )
        $picked | Should Be 'ZapretGUI.exe'
    }

    It 'falls back to a versioned executable' {
        $picked = Select-GuiUpdateAsset @(
            'README.md',
            'ZapretGUI-1.0.28-win10-win11.exe'
        )
        $picked | Should Be 'ZapretGUI-1.0.28-win10-win11.exe'
    }

    It 'returns nothing when no executable matches' {
        Select-GuiUpdateAsset @('SHA256SUMS.txt', 'README.md') | Should BeNullOrEmpty
    }
}

Describe 'Get-GuiUpdateHashFromSums' {
    It 'reads the exact ZapretGUI.exe line' {
        $exact = ('a' * 64)
        $other = ('b' * 64)
        $text = @"
$other  ZapretGUI-1.0.28-win10-win11.exe
$exact  ZapretGUI.exe
"@
        Get-GuiUpdateHashFromSums $text | Should Be $exact
    }

    It 'falls back to a versioned executable line' {
        $other = ('c' * 64)
        $text = "$other  ZapretGUI-1.0.30-win10-win11.exe"
        Get-GuiUpdateHashFromSums $text | Should Be $other
    }
}

Describe 'Select-BestStrategy' {
    It 'ignores a score of zero' {
        $winner = Select-BestStrategy @(
            @{ Name = 'general.bat'; Ok = 0 }
        )
        $winner | Should BeNullOrEmpty
    }

    It 'keeps the highest positive score' {
        $winner = Select-BestStrategy @(
            @{ Name = 'alt.bat'; Ok = 1 },
            @{ Name = 'general.bat'; Ok = 4 },
            @{ Name = 'empty.bat'; Ok = 0 }
        )
        $winner | Should Be 'general.bat'
    }
}

Describe 'ConvertTo-HostName' {
    It 'normalizes a URL and rejects an IPv4 address' {
        ConvertTo-HostName 'https://www.YouTube.com/watch?v=1' | Should Be 'youtube.com'
        ConvertTo-HostName 'example.com:443' | Should Be 'example.com'
        ConvertTo-HostName '1.2.3.4' | Should BeNullOrEmpty
    }
}
