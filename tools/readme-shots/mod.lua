---@type GearModManifest
return {
    id = 'shots',
    name = 'README screenshots',
    version = '1.0.0',
    author = 'kirides',
    description = 'Automation only: takes the screenshots of the README (see run.ps1).',
    automation = true,
    priority = 200,
    config = {phase = 'autosave'},
}
