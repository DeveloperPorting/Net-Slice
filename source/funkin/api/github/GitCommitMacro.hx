package funkin.api.github;

/**
 * A standalone class used solely for running compilation macros.
 * Do not import OpenFL or game packages here!
 */
class GitCommitMacro
{
  macro public static function getGitCommitHash():haxe.macro.Expr.ExprOf<String>
  {
    try
    {
      var process = new sys.io.Process("git", ["rev-parse", "--short", "HEAD"]);
      var hash = process.stdout.readLine();
      process.close();
      return macro $v{hash};
    }
    catch (e:Dynamic)
    {
      return macro $v{"UNKNOWN"};
    }
  }
}
