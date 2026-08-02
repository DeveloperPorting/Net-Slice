package funkin.play.character;

import flixel.math.FlxPoint;
import funkin.modding.events.ScriptEvent;
import funkin.data.character.CharacterData;
import funkin.data.character.CharacterData.CharacterDataParser;
import funkin.data.character.CharacterData.CharacterRenderType;
import funkin.play.stage.Bopper;
import funkin.play.notes.NoteDirection;
import funkin.play.notes.notekind.NoteKind;
import funkin.play.notes.notekind.NoteKindManager;
import funkin.play.stage.Stage;

/**
 * A Character is a stage prop which bops to the music as well as controlled by the strumlines.
 *
 * Remember: The character's origin is at its FEET. (horizontal center, vertical bottom)
 */
class BaseCharacter extends Bopper
{
  public var characterId(default, null):String;
  public var characterName(default, null):String;

  public var characterType(default, set):CharacterType = OTHER;

  function set_characterType(value:CharacterType):CharacterType
  {
    return this.characterType = value;
  }

  public var holdTimer:Float = 0;
  public var isDead:Bool = false;
  public var debug:Bool = false;
  public var currentStage:Null<Stage> = null;
  public var curNoteKind:NoteKind;
  public var comboNoteCounts(default, null):Array<Int>;
  public var dropNoteCounts(default, null):Array<Int>;

  @:allow(funkin.ui.debug.anim.DebugBoundingState)
  final _data:CharacterData;
  final singTimeSteps:Float;

  private var _cachedOrigin:FlxPoint = new FlxPoint();
  private var _cachedCorner:FlxPoint = new FlxPoint();
  private var _cachedFeet:FlxPoint = new FlxPoint();

  public var characterOrigin(get, never):FlxPoint;
  function get_characterOrigin():FlxPoint
  {
    _cachedOrigin.set(width / 2, height);
    return _cachedOrigin;
  }

  public var cornerPosition(get, set):FlxPoint;
  function get_cornerPosition():FlxPoint
  {
    _cachedCorner.set(x, y);
    return _cachedCorner;
  }

  function set_cornerPosition(value:FlxPoint):FlxPoint
  {
    var xDiff:Float = value.x - this.x;
    var yDiff:Float = value.y - this.y;

    this.cameraFocusPoint.x += xDiff;
    this.cameraFocusPoint.y += yDiff;

    super.set_x(value.x);
    super.set_y(value.y);

    return value;
  }

  public var feetPosition(get, never):FlxPoint;
  function get_feetPosition():FlxPoint
  {
    var origin = characterOrigin;
    _cachedFeet.set(x + origin.x, y + origin.y);
    return _cachedFeet;
  }

  public var cameraFocusPoint(default, null):FlxPoint = new FlxPoint(0, 0);

  override function set_x(value:Float):Float
  {
    if (value == this.x) return value;
    this.cameraFocusPoint.x += (value - this.x);
    return super.set_x(value);
  }

  override function set_y(value:Float):Float
  {
    if (value == this.y) return value;
    this.cameraFocusPoint.y += (value - this.y);
    return super.set_y(value);
  }

  public function new(id:String, renderType:CharacterRenderType)
  {
    super(CharacterDataParser.DEFAULT_DANCEEVERY);

    this.characterId = id;
    ignoreExclusionPref = ["sing"];

    _data = CharacterDataParser.fetchCharacterData(this.characterId);
    if (_data == null)
    {
      throw 'Could not find character data for characterId: $characterId';
    }
    else if (_data.renderType != renderType)
    {
      throw 'Render type mismatch for character ($characterId): expected ${renderType}, got ${_data.renderType}';
    }
    else
    {
      this.characterName = _data.name;
      this.name = _data.name;
      this.danceEvery = _data.danceEvery;
      this.singTimeSteps = _data.singTime;
      this.globalOffsets = _data.offsets;
      this.flipX = _data.flipX;
    }

    if (PlayState.instance != null) currentStage = PlayState.instance.currentStage;

    shouldBop = false;
  }

  public function getDeathCameraOffsets():Array<Float> return _data.death?.cameraOffsets ?? [0.0, 0.0];
  public function getBaseScale():Float return _data.scale;
  public function getDeathCameraZoom():Float return _data.death?.cameraZoom ?? 1.0;
  public function getDeathPreTransitionDelay():Float return _data.death?.preTransitionDelay ?? 0.0;
  public function getDataFlipX():Bool return _data.flipX;

  function findCountAnimations(prefix:String):Array<Int>
  {
    var result:Array<Int> = [];
    for (anim in this.animation.getNameList())
    {
      if (anim.startsWith(prefix))
      {
        var comboNum:Null<Int> = Std.parseInt(anim.substring(prefix.length));
        if (comboNum != null) result.push(comboNum);
      }
    }
    result.sort((a, b) -> a - b);
    return result;
  }

  public function resetCharacter(resetCamera:Bool = true):Void
  {
    this.resetPosition();
    this.danceEvery = _data.danceEvery;
    this.dance(true);
    this.updateHitbox();
    if (resetCamera) this.resetCameraFocusPoint();
  }

  public function setScale(scale:Null<Float>):Void
  {
    if (scale == null) scale = 1.0;
    var feetPos = feetPosition; // Guarda o valor usando o cache
    var ftX = feetPos.x;
    var ftY = feetPos.y;
    var org = characterOrigin;

    this.scale.set(scale, scale);
    this.updateHitbox();
    
    this.x = ftX - org.x + globalOffsets[0];
    this.y = ftY - org.y + globalOffsets[1];
  }

  var characterCameraOffsets(get, never):Array<Float>;
  function get_characterCameraOffsets():Array<Float> return _data.cameraOffsets;

  override function onCreate(event:ScriptEvent):Void
  {
    super.onCreate(event);
    this.dance(true);
    this.updateHitbox();
    this.resetCameraFocusPoint();

    this.comboNoteCounts = findCountAnimations('combo');
    this.dropNoteCounts = findCountAnimations('drop');
    if (comboNoteCounts.length > 0) log('Character $characterId plays Combo animation at ${this.comboNoteCounts.join(', ')}');
    if (dropNoteCounts.length > 0) log('Character $characterId plays Drop animation at ${this.dropNoteCounts.join(', ')}');

    super.onCreate(event);
  }

  override function onAnimationFinished(animationName:String):Void
  {
    super.onAnimationFinished(animationName);

    if ((animationName.endsWith(Constants.ANIMATION_END_SUFFIX) && !animationName.startsWith('idle') && !animationName.startsWith('dance'))
      || animationName.startsWith('combo')
      || animationName.startsWith('drop'))
    {
      this.dance(true);
    }
  }

  public function resetCameraFocusPoint():Void
  {
    var charCenterX = this.originalPosition.x + this.width / 2;
    var charCenterY = this.originalPosition.y + this.height / 2;
    this.cameraFocusPoint.set(charCenterX + _data.cameraOffsets[0], charCenterY + _data.cameraOffsets[1]);
  }

  public function getHealthIconId():String return _data?.healthIcon?.id ?? Constants.DEFAULT_HEALTH_ICON;

  public function initHealthIcon(isOpponent:Bool):Void
  {
    var targetIcon = isOpponent ? PlayState.instance.iconP2 : PlayState.instance.iconP1;
    if (targetIcon == null)
    {
      log(' WARNING '.warning() + ' Player ${isOpponent ? 2 : 1} ($characterId) health icon not found!');
      return;
    }
    
    targetIcon.configure(_data?.healthIcon);
    if (!isOpponent) targetIcon.flipX = !targetIcon.flipX;
  }

  public override function onUpdate(event:UpdateScriptEvent):Void
  {
    super.onUpdate(event);

    if (this.characterType == BF && justPressedNote()) holdTimer = 0;
    if (isDead) return;

    var curAnim:String = getCurrentAnimation();
    var animFinished:Bool = isAnimationFinished();

    if (animFinished && curAnim != null)
    {
      if (!curAnim.endsWith(Constants.ANIMATION_HOLD_SUFFIX))
      {
        var holdAnim = curAnim + Constants.ANIMATION_HOLD_SUFFIX;
        if (hasAnimation(holdAnim)) playAnimation(holdAnim);
      }
    }

    if (isSinging(curAnim))
    {
      holdTimer += event.elapsed;
      var singTimeSec:Float = singTimeSteps * (Conductor.instance.stepLengthMs / Constants.MS_PER_SEC);

      if (curAnim != null && curAnim.endsWith('miss')) singTimeSec *= 2;

      var shouldStopSinging:Bool = (this.characterType == BF) ? !isHoldingNote() : true;

      FlxG.watch.addQuick('singTimeSec-${characterId}', singTimeSec);
      if (holdTimer > singTimeSec && shouldStopSinging)
      {
        holdTimer = 0;
        if (curAnim != null && curAnim.endsWith(Constants.ANIMATION_HOLD_SUFFIX)) 
        {
           curAnim = curAnim.substring(0, curAnim.length - Constants.ANIMATION_HOLD_SUFFIX.length);
        }

        var endAnimation:String = curAnim + Constants.ANIMATION_END_SUFFIX;
        if (hasAnimation(endAnimation)) playAnimation(endAnimation);
        else dance(true);
      }
    }
    else holdTimer = 0;
    
    FlxG.watch.addQuick('holdTimer-${characterId}', holdTimer);
  }

  public inline function isSinging(?currentAnimation:String):Bool
  {
    if (currentAnimation == null) currentAnimation = getCurrentAnimation();
    return currentAnimation != null && currentAnimation.startsWith('sing') && !currentAnimation.endsWith(Constants.ANIMATION_END_SUFFIX);
  }

  override function dance(force:Bool = false):Void
  {
    if (isDead) return;

    if (!force)
    {
      var curAnim = getCurrentAnimation();
      if (isSinging(curAnim)) return;
      if (curAnim != null && !curAnim.startsWith('dance') && !curAnim.startsWith('idle') && !isAnimationFinished()) return;
    }
    super.dance();
  }

  function justPressedNote(player:Int = 1):Bool
  {
    var ctrl = (player == 1) ? PlayerSettings.player1.controls : PlayerSettings.player2.controls;
    return ctrl.NOTE_LEFT_P || ctrl.NOTE_DOWN_P || ctrl.NOTE_UP_P || ctrl.NOTE_RIGHT_P;
  }

  function isHoldingNote(player:Int = 1):Bool
  {
    var ctrl = (player == 1) ? PlayerSettings.player1.controls : PlayerSettings.player2.controls;
    return ctrl.NOTE_LEFT || ctrl.NOTE_DOWN || ctrl.NOTE_UP || ctrl.NOTE_RIGHT;
  }

  public override function onNoteHit(event:HitNoteScriptEvent)
  {
    super.onNoteHit(event);
    if (event.eventCanceled) return;
    
    curNoteKind = NoteKindManager.getNoteKind(event.note.noteData.kind);

    var isPlayerHit = (event.note.noteData.getMustHitNote() && characterType == BF);
    var isCpuHit = (!event.note.noteData.getMustHitNote() && characterType == DAD);

    if (isPlayerHit || isCpuHit)
    {
      if (curNoteKind == null || !curNoteKind.noanim)
      {
        this.playSingAnimation(event.note.noteData.getDirection(), false, curNoteKind?.suffix);
        holdTimer = 0;
      }
    }
    else if (characterType == GF && event.note.noteData.getMustHitNote())
    {
      if (event.judgement == 'sick' || event.judgement == 'good') playComboAnimation(event.comboCount);
      else playComboDropAnimation(event.comboCount);
    }
  }

  public override function onNoteMiss(event:NoteScriptEvent)
  {
    super.onNoteMiss(event);
    if (event.eventCanceled) return;

    var isPlayerHit = (event.note.noteData.getMustHitNote() && characterType == BF);
    var isCpuHit = (!event.note.noteData.getMustHitNote() && characterType == DAD);

    if (isPlayerHit || isCpuHit) this.playSingAnimation(event.note.noteData.getDirection(), true);
    else if (event.note.noteData.getMustHitNote() && characterType == GF) playComboDropAnimation(event.comboCount);
  }

  public override function onNoteHoldDrop(event:HoldNoteScriptEvent)
  {
    super.onNoteHoldDrop(event);
    if (event.eventCanceled) return;

    var isPlayerHit = (event.holdNote.noteData.getMustHitNote() && characterType == BF);
    var isCpuHit = (!event.holdNote.noteData.getMustHitNote() && characterType == DAD);

    if (isPlayerHit || isCpuHit) this.playSingAnimation(event.holdNote.noteData.getDirection(), true);
    else if (event.holdNote.noteData.getMustHitNote() && event.isComboBreak && characterType == GF) playComboDropAnimation(event.comboCount);
  }

  function playComboAnimation(comboCount:Int):Void
  {
    var comboAnim = 'combo${comboCount}';
    if (hasAnimation(comboAnim))
    {
      log('Playing combo animation "${comboAnim}"');
      this.playAnimation(comboAnim, true, true);
    }
  }

  function playComboDropAnimation(comboCount:Int):Void
  {
    var dropAnim:Null<String> = null;
    for (count in dropNoteCounts)
    {
      if (comboCount >= count) dropAnim = 'drop${count}';
    }

    if (dropAnim != null)
    {
      log('Playing combo drop animation "${dropAnim}"');
      this.playAnimation(dropAnim, true, true);
    }
  }

  public override function onNoteGhostMiss(event:GhostMissNoteScriptEvent):Void
  {
    super.onNoteGhostMiss(event);
    if (event.eventCanceled || !event.playAnim) return;

    if (characterType == BF) this.playSingAnimation(event.dir, true);
  }

  public override function onDestroy(event:ScriptEvent):Void
  {
    this.characterType = OTHER;
  }

  public function playSingAnimation(dir:NoteDirection, miss:Bool = false, ?suffix:String = ''):Void
  {
    var animSuffix = (suffix != null && suffix != '') ? '-${suffix}' : '';
    var anim:String = 'sing${dir.nameUpper}${miss ? 'miss' : ''}${animSuffix}';
    playAnimation(anim, true);
  }

  public override function playAnimation(name:String, restart:Bool = false, ignoreOther:Bool = false, reversed:Bool = false):Void
  {
    super.playAnimation(name, restart, ignoreOther, reversed);
  }

  public function getDeathQuote():Null<String> return null;

  static function log(message:String):Void trace(' CHARACTER '.bold().bg_blue() + ' $message');
}

enum CharacterType
{
  BF;
  DAD;
  GF;
  OTHER;
}