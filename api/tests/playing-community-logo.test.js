const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function source(relativePath) {
  return fs.readFileSync(path.join(__dirname, '..', relativePath), 'utf8');
}

test('playing-community crests use an uploaded private media asset', () => {
  const schema = source('prisma/schema.prisma');
  const controller = source('src/controllers/organization.controller.ts');
  const routes = source('src/routes/organization.routes.ts');
  const server = source('src/server.ts');

  assert.match(schema, /PLAYING_COMMUNITY_LOGO/);
  assert.match(
    routes,
    /teams\/:id\/playing-community-logo[\s\S]*playerFileUpload\.single\('file'\)[\s\S]*uploadPlayingCommunityLogo/,
  );
  assert.match(
    controller,
    /uploadPlayingCommunityLogo[\s\S]*uploadPrivate[\s\S]*kind:\s*'PLAYING_COMMUNITY_LOGO'[\s\S]*playingCommunityLogoUrl/,
  );
  assert.match(
    controller,
    /removePlayingCommunityLogo[\s\S]*playingCommunityLogoUrl:\s*null/,
  );
  assert.ok(
    server.indexOf("'/media/playing-community-logo/:teamId'") <
      server.indexOf("'/media/:id'"),
    'the specific public crest route must be registered before /media/:id',
  );
});

test('Flutter team editor offers an image upload instead of a crest URL field', () => {
  const page = source(
    '../fc_teugn_app/lib/features/organization/organization_page.dart',
  );
  const repository = source('../fc_teugn_app/lib/core/data_repository.dart');

  assert.doesNotMatch(page, /Wappen-URL/);
  assert.match(page, /_pickPlayingCommunityLogo[\s\S]*ImagePicker\(\)\.pickImage/);
  assert.match(page, /Wappen der Spielgemeinschaft/);
  assert.match(repository, /uploadPlayingCommunityLogo[\s\S]*MultipartFile\.fromBytes/);
  assert.match(repository, /removePlayingCommunityLogo/);
});
