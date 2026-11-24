enum AppThemeStyle {
  tide,
  ocean,
  sky,
  ember,
  forest,
  dune,
  aurora,
  night,
  abyss,
  graphite,
  darkGreen,
  darkWood,
  monochrome;

  bool get isDark => switch (this) {
        night || abyss || graphite || darkGreen || darkWood => true,
        tide ||
        ocean ||
        sky ||
        ember ||
        forest ||
        dune ||
        aurora ||
        monochrome =>
          false,
      };

  String get label => switch (this) {
        tide => '潮汐',
        ocean => '海洋',
        sky => '晴空',
        ember => '余烬',
        forest => '森林',
        dune => '沙丘',
        aurora => '极光',
        night => '夜色',
        abyss => '墨绿',
        graphite => '石墨',
        darkGreen => '深林',
        darkWood => '沉木',
        monochrome => '黑白极简',
      };
}
