package funkin;

import flixel.graphics.FlxGraphic;
import flixel.FlxG;
import funkin.play.notes.notestyle.NoteStyle;
import openfl.utils.AssetType;
import openfl.Assets;
import openfl.system.System;
import openfl.media.Sound;
import lime.app.Future;
import lime.app.Promise;

/**
 * Handles caching of textures and sounds for the game.
 * Optimized to prevent graphic.destroy() crashes while maintaining a low memory footprint.
 */
@:nullSafety
class FunkinMemory
{
  static var permanentCachedTextures:Map<String, FlxGraphic> = [];
  static var currentCachedTextures:Map<String, FlxGraphic> = [];
  static var previousCachedTextures:Map<String, FlxGraphic> = [];

  static var permanentCachedSounds:Map<String, Sound> = [];
  static var currentCachedSounds:Map<String, Sound> = [];
  static var previousCachedSounds:Map<String, Sound> = [];

  /**
   * Caches textures that are always required.
   */
  public static inline function initialCache():Void
  {
    var allImages:Array<String> = Assets.list();

    for (file in allImages)
    {
      if (!(file.endsWith(".png") #if FEATURE_COMPRESSED_TEXTURES || file.endsWith(".astc") #end)
        || file.contains("chart-editor")
        || !file.contains("ui/"))
      {
        continue;
      }

      file = file.replace(" ", "");

      if (file.contains("shared") || Assets.exists('shared:$file', AssetType.IMAGE))
      {
        file = 'shared:$file';
      }
      permanentCacheTexture(file);
    }

    permanentCacheTexture(Paths.image("healthBar"));
    permanentCacheTexture(Paths.image("menuDesat"));
    permanentCacheTexture(Paths.image("notes", "shared"));
    permanentCacheTexture(Paths.image("noteSplashes", "shared"));
    permanentCacheTexture(Paths.image("noteStrumline", "shared"));
    permanentCacheTexture(Paths.image("NOTE_hold_assets"));
    
    permanentCacheTexture(Paths.image("fonts/bold", null));
    permanentCacheTexture(Paths.image("fonts/default", null));
    permanentCacheTexture(Paths.image("fonts/freeplay-clear", null));

    var allSounds:Array<String> = Assets.list(AssetType.SOUND);

    for (file in allSounds)
    {
      if (!file.endsWith(".ogg") || !file.contains("countdown/")) continue;

      file = file.replace(" ", "");

      if (file.contains("shared") || Assets.exists('shared:$file', AssetType.SOUND))
      {
        file = 'shared:$file';
      }

      permanentCacheSound(file);
    }

    permanentCacheSound(Paths.sound("cancelMenu"));
    permanentCacheSound(Paths.sound("confirmMenu"));
    permanentCacheSound(Paths.sound("screenshot"));
    permanentCacheSound(Paths.sound("scrollMenu"));
    permanentCacheSound(Paths.sound("soundtray/Voldown"));
    permanentCacheSound(Paths.sound("soundtray/VolMAX"));
    permanentCacheSound(Paths.sound("soundtray/Volup"));
    permanentCacheSound(Paths.music("freakyMenu/freakyMenu"));
    permanentCacheSound(Paths.music("offsetsLoop/offsetsLoop"));
    permanentCacheSound(Paths.music("offsetsLoop/drumsLoop"));
    permanentCacheSound(Paths.sound("missnote1", "shared"));
    permanentCacheSound(Paths.sound("missnote2", "shared"));
    permanentCacheSound(Paths.sound("missnote3", "shared"));
  }

  /**
   * Clears the current texture and sound caches.
   * @param callGarbageCollector Whether to call the system's garbage collector after purging.
   */
  public static inline function purgeCache(callGarbageCollector:Bool = false):Void
  {
    preparePurgeTextureCache();
    purgeTextureCache();
    preparePurgeSoundCache();
    purgeSoundCache();
    
    #if (cpp || neko || hl)
    if (callGarbageCollector) funkin.util.MemoryUtil.collect(true);
    #end
  }
  
  /**
   * Clears absolutely all assets that are not being used.
   * Great for calling at the end or beginning of a State to avoid leaks.
   */
  public static inline function clearUnused():Void
  {
    var keysToRemove:Array<String> = [];

    @:privateAccess
    for (key in FlxG.bitmap._cache.keys())
    {
      var obj:Null<FlxGraphic> = FlxG.bitmap.get(key);
      if (obj != null && obj.useCount <= 0 && !obj.persist && !permanentCachedTextures.exists(key) && !currentCachedTextures.exists(key))
      {
        if (!key.contains("fonts") && !key.contains("freeplay") && !key.contains("albumRoll"))
        {
          keysToRemove.push(key);
        }
      }
    }

    for (key in keysToRemove)
    {
      log('Sweeping unused graphic $key');
      
      FlxG.bitmap.removeByKey(key); 
      previousCachedTextures.remove(key);
      Assets.cache.clear(key);
    }
    
    var soundKeysToRemove:Array<String> = [];
    for (key in currentCachedSounds.keys())
    {
       if (!permanentCachedSounds.exists(key)) soundKeysToRemove.push(key);
    }
    
    for (key in soundKeysToRemove)
    {
        Assets.cache.removeSound(key);
        Assets.cache.clear(key);
        currentCachedSounds.remove(key);
        previousCachedSounds.remove(key);
    }

    System.gc();
  }  

  ///// TEXTURES /////

  public static function cacheTexture(key:String):Void
  {
    if (currentCachedTextures.exists(key)) return;

    if (previousCachedTextures.exists(key))
    {
      var graphic:Null<FlxGraphic> = previousCachedTextures.get(key);
      previousCachedTextures.remove(key);
      if (graphic != null) currentCachedTextures.set(key, graphic);
      return;
    }

    var graphic:Null<FlxGraphic> = FlxGraphic.fromAssetKey(key, false, null, true);
    if (graphic == null)
    {
      FlxG.log.warn('Failed to cache graphic: $key');
      return;
    }

    log('Cached asset $key');
    graphic.persist = true;
    currentCachedTextures.set(key, graphic);
    forceRender(graphic);
  }

  static function permanentCacheTexture(key:String):Void
  {
    if (permanentCachedTextures.exists(key)) return;

    var graphic:Null<FlxGraphic> = FlxGraphic.fromAssetKey(key, false, null, true);
    if (graphic == null)
    {
      FlxG.log.warn('Failed to cache graphic: $key');
      return;
    }

    log('Cached graphic $key');
    graphic.persist = true;
    permanentCachedTextures.set(key, graphic);
    forceRender(graphic);
    currentCachedTextures.set(key, graphic);
  }

  public static function getCachedGraphic(path:String):Null<FlxGraphic>
  {
    if (permanentCachedTextures.exists(path)) return permanentCachedTextures.get(path);
    if (currentCachedTextures.exists(path)) return currentCachedTextures.get(path);
    if (previousCachedTextures.exists(path)) return previousCachedTextures.get(path);
    return null;
  }

  public inline static function preparePurgeTextureCache():Void
  {
    previousCachedTextures = currentCachedTextures.copy();

    for (graphicKey in previousCachedTextures.keys())
    {
      if (permanentCachedTextures.exists(graphicKey))
      {
        previousCachedTextures.remove(graphicKey);
      }
    }

    currentCachedTextures = permanentCachedTextures.copy();
  }

  public static function purgeTextureCache():Void
  {
    for (graphicKey in previousCachedTextures.keys())
    {
      if (permanentCachedTextures.exists(graphicKey) || graphicKey.contains("fonts"))
      {
        previousCachedTextures.remove(graphicKey);
        continue;
      }

      var graphic:Null<FlxGraphic> = previousCachedTextures.get(graphicKey);
      if (graphic != null)
      {
        graphic.persist = false;
        if (graphic.useCount <= 0)
        {
          // Removes from FlxG and handles disposal safely. 
          // Do NOT call graphic.destroy() here to prevent crashes!
          FlxG.bitmap.remove(graphic); 
          Assets.cache.clear(graphicKey);
        }
      }
      previousCachedTextures.remove(graphicKey);
    }

    var keysToRemove:Array<String> = [];

    @:privateAccess
    if (FlxG.bitmap._cache != null)
    {
      for (key in FlxG.bitmap._cache.keys())
      {
        var obj:Null<FlxGraphic> = FlxG.bitmap.get(key);

        if (obj == null || obj.persist || permanentCachedTextures.exists(key) || key.contains("fonts"))
        {
          continue;
        }

        if (obj.useCount <= 0) keysToRemove.push(key);
      }
    }

    for (key in keysToRemove)
    {
      FlxG.bitmap.removeByKey(key);
      Assets.cache.clear(key);
    }
  }

  private static function forceRender(graphic:FlxGraphic):Void
  {
    if (graphic == null) return;

    var bmp:Null<FlxGraphic> = FlxG.bitmap.get(graphic.key);
    if (bmp != null && bmp.bitmap != null) var _:Int = bmp.bitmap.width; 

    var sprite = new flixel.FlxSprite();
    sprite.loadGraphic(graphic);
    sprite.draw(); 
    graphic.bitmap?.getTexture(FlxG.stage.context3D); 
    sprite.destroy();
  }

  public static function isTextureCached(key:String):Bool
  {
    return FlxG.bitmap.get(key) != null
      && (permanentCachedTextures.exists(key) || currentCachedTextures.exists(key) || previousCachedTextures.exists(key));
  }

  ///// NOTE STYLE //////

  public static function cacheNoteStyle(style:NoteStyle):Void
  {
    cacheTexture(Paths.image(style.getNoteAssetPath() ?? "note"));
    cacheTexture(style.getHoldNoteAssetPath() ?? "noteHold");
    cacheTexture(Paths.image(style.getStrumlineAssetPath() ?? "strumline"));
    cacheTexture(Paths.image(style.getSplashAssetPath() ?? "noteSplash"));

    cacheTexture(Paths.image(style.getHoldCoverDirectionAssetPath(LEFT) ?? "LEFT"));
    cacheTexture(Paths.image(style.getHoldCoverDirectionAssetPath(RIGHT) ?? "RIGHT"));
    cacheTexture(Paths.image(style.getHoldCoverDirectionAssetPath(UP) ?? "UP"));
    cacheTexture(Paths.image(style.getHoldCoverDirectionAssetPath(DOWN) ?? "DOWN"));

    cacheTexture(Paths.image(style.buildCountdownSpritePath(TWO) ?? "TWO"));
    cacheTexture(Paths.image(style.buildCountdownSpritePath(ONE) ?? "ONE"));
    cacheTexture(Paths.image(style.buildCountdownSpritePath(GO) ?? "GO"));

    cacheSound(style.getCountdownSoundPath(THREE) ?? "THREE");
    cacheSound(style.getCountdownSoundPath(TWO) ?? "TWO");
    cacheSound(style.getCountdownSoundPath(ONE) ?? "ONE");
    cacheSound(style.getCountdownSoundPath(GO) ?? "GO");

    cacheTexture(Paths.image(style.buildJudgementSpritePath("sick") ?? 'sick'));
    cacheTexture(Paths.image(style.buildJudgementSpritePath("good") ?? 'good'));
    cacheTexture(Paths.image(style.buildJudgementSpritePath("bad") ?? 'bad'));
    cacheTexture(Paths.image(style.buildJudgementSpritePath("shit") ?? 'shit'));

    for (i in 0...10)
    {
        cacheTexture(Paths.image(style.buildComboNumSpritePath(i) ?? '$i'));
    }
  }

  ///// SOUND //////

  public static function cacheSound(key:String):Void
  {
    if (currentCachedSounds.exists(key)) return;

    if (previousCachedSounds.exists(key))
    {
      var sound:Null<Sound> = previousCachedSounds.get(key);
      previousCachedSounds.remove(key);
      if (sound != null) currentCachedSounds.set(key, sound);
      return;
    }

    var sound:Null<Sound> = Assets.getSound(key, true);
    if (sound != null) currentCachedSounds.set(key, sound);
  }

  public static function permanentCacheSound(key:String):Void
  {
    if (permanentCachedSounds.exists(key)) return;

    var sound:Null<Sound> = Assets.getSound(key, true);
    if (sound != null)
    {
      permanentCachedSounds.set(key, sound);
      currentCachedSounds.set(key, sound);
    }
  }

  public static function preparePurgeSoundCache():Void
  {
    previousCachedSounds = currentCachedSounds.copy();

    for (key in previousCachedSounds.keys())
    {
      if (permanentCachedSounds.exists(key))
      {
        previousCachedSounds.remove(key);
      }
    }

    currentCachedSounds = permanentCachedSounds.copy();
  }

  public static inline function purgeSoundCache():Void
  {
    for (key in previousCachedSounds.keys())
    {
      if (permanentCachedSounds.exists(key))
      {
        previousCachedSounds.remove(key);
        continue;
      }

      var sound:Null<Sound> = previousCachedSounds.get(key);
      if (sound != null)
      {
        Assets.cache.removeSound(key);
        Assets.cache.clear(key);
        previousCachedSounds.remove(key);
      }
    }
    
    var freakyKey = Paths.music("freakyMenu/freakyMenu");
    var sound:Null<Sound> = Assets.getSound(freakyKey, true);
    if (sound != null)
    {
      permanentCachedSounds.set(freakyKey, sound);
      currentCachedSounds.set(freakyKey, sound);
    }
  }

  ///// MISC /////

  public static inline function clearFreeplay():Void
  {
    preparePurgeTextureCache();
    purgeTextureCache();
    preparePurgeSoundCache();
    purgeSoundCache();
    System.gc();
  }

  public static inline function clearStickers():Void
  {
    preparePurgeTextureCache();
    purgeTextureCache();
    System.gc();
  }

  private static function log(message:String):Void
  {
    trace(' MEMORY '.bg_bright_lilac().bold() + ' ${message}');
  }
}