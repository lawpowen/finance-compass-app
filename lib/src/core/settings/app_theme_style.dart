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
  monochrome,
  dopamine,
  liquidGlass;

  static const List<AppThemeStyle> selectableStyles = [
    AppThemeStyle.monochrome,
    AppThemeStyle.dopamine,
    AppThemeStyle.liquidGlass,
  ];

  static AppThemeStyle normalize(String? raw) => selectableStyles.firstWhere(
        (style) => style.name == raw,
        orElse: () => AppThemeStyle.monochrome,
      );

  bool get isDark => switch (this) {
        night || abyss || graphite || darkGreen || darkWood => true,
        tide ||
        ocean ||
        sky ||
        ember ||
        forest ||
        dune ||
        aurora ||
        monochrome ||
        dopamine ||
        liquidGlass =>
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
        dopamine => '多巴胺',
        liquidGlass => '苹果液态玻璃',
      };

  String get description => switch (this) {
        monochrome => '暖白纸面与克制语义墨色，灰阶圆环专注数字',
        dopamine => '薄荷、杏橙与薰衣草撞色，高辨识明快卡片',
        liquidGlass => '冰蓝清透质感与玻璃胶囊，柔和通透高可读',
        _ => '已归档主题（自动回退至黑白极简）',
      };
}
