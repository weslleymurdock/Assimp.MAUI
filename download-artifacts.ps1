New-Item -ItemType Directory -Force -Path "artifacts" | Out-Null

$branch = (git branch --show-current).Trim()
$repo = (gh repo view --json owner, name --jq '"\(.owner.login)/\(.name)"').Trim()
$runId = (gh run list --branch $branch --limit 1 --json databaseId --jq '.[0].databaseId').Trim()

if (-not $runId) {
    Write-Error "Nenhum workflow encontrado para a branch atual ($branch)."
    exit 1
}

$artifactsJson = gh api "repos/$repo/actions/runs/$runId/artifacts" --jq '.artifacts[] | select(.name | test("^assimp-")) | .name'
$artifactNames = @($artifactsJson -split "`r?`n" | Where-Object { $_ -ne "" })

foreach ($name in $artifactNames) {
    # Remove a extensão .zip do nome da pasta (caso o artefato tenha esse nome)
    $folderName = $name -replace '(?i)\.zip$', ''
    $targetDir = "./artifacts/$folderName"
    
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    
    Write-Host "Baixando $name..."
    gh run download $runId -n $name -D $targetDir
    
    # Procura por arquivos .zip dentro do diretório recém-baixado
    $zipFiles = Get-ChildItem -Path $targetDir -Filter "*.zip" -File
    
    foreach ($zip in $zipFiles) {
        Write-Host "Extraindo $($zip.Name)..."
        # Extrai o conteúdo do zip diretamente na pasta do artefato
        Expand-Archive -Path $zip.FullName -DestinationPath $targetDir -Force
        
        # Remove o arquivo .zip original após a extração para manter a pasta limpa
        Remove-Item -Path $zip.FullName -Force
    }
}

Write-Host "Download e extração concluídos com sucesso!"