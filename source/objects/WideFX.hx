package objects;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;

/**
 * Efectos de cámara estilo V-Slice que cubren TODO el ancho real de la pantalla,
 * con widescreen activado o desactivado.
 *
 * Todo se dibuja en una cámara aparte (camFX) marcada como "ancho completo" en
 * MobileScaleMode, y el tamaño se recalcula en cada frame con el ancho real de esa cámara.
 */
class WideFX extends FlxGroup
{
	public var cam:FlxCamera;

	/** 0 = bandas fuera, 1 = bandas dentro. */
	public var barAmount:Float = 0;
	public var barRatio:Float = 0.12; // alto de cada banda respecto a 720

	var topBar:FlxSprite;
	var bottomBar:FlxSprite;
	var flashSpr:FlxSprite;
	var fadeSpr:FlxSprite;

	public function new(cam:FlxCamera)
	{
		super();
		this.cam = cam;

		topBar = makeLayer(FlxColor.BLACK);
		bottomBar = makeLayer(FlxColor.BLACK);
		fadeSpr = makeLayer(FlxColor.BLACK);
		flashSpr = makeLayer(FlxColor.WHITE);
		fadeSpr.alpha = 0;
		flashSpr.alpha = 0;
	}

	function makeLayer(color:FlxColor):FlxSprite
	{
		var spr = new FlxSprite().makeGraphic(1, 1, color);
		spr.scrollFactor.set();
		spr.cameras = [cam];
		add(spr);
		return spr;
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		var w:Float = cam.width;
		var h:Float = FlxG.height;
		var barH:Float = Math.round(h * barRatio);

		stretch(topBar, w, barH, 0, -barH + barH * barAmount);
		stretch(bottomBar, w, barH, 0, h - barH * barAmount);
		stretch(fadeSpr, w, h, 0, 0);
		stretch(flashSpr, w, h, 0, 0);
	}

	inline function stretch(spr:FlxSprite, w:Float, h:Float, x:Float, y:Float):Void
	{
		spr.scale.set(w, h);
		spr.updateHitbox();
		spr.setPosition(x, y);
	}

	/** Bandas negras cinematográficas. */
	public function bars(show:Bool, time:Float = 0.6):Void
	{
		FlxTween.cancelTweensOf(this, ['barAmount']);
		if (time <= 0) barAmount = show ? 1 : 0;
		else FlxTween.tween(this, {barAmount: show ? 1 : 0}, time, {ease: FlxEase.quartOut});
	}

	/** Flash de color. Con "Flashing Lights" desactivado se hace mucho más suave. */
	public function flash(color:FlxColor = 0xFFFF2BD6, time:Float = 0.4):Void
	{
		flashSpr.color = color;
		flashSpr.alpha = ClientPrefs.data.flashing ? 1 : 0.25;
		FlxTween.cancelTweensOf(flashSpr);
		FlxTween.tween(flashSpr, {alpha: 0}, Math.max(0.01, time), {ease: FlxEase.quadOut});
	}

	/** Pantalla negra: oscurece (true) o aclara (false). */
	public function fade(toBlack:Bool, time:Float = 1):Void
	{
		FlxTween.cancelTweensOf(fadeSpr);
		if (time <= 0) fadeSpr.alpha = toBlack ? 1 : 0;
		else FlxTween.tween(fadeSpr, {alpha: toBlack ? 1 : 0}, time);
	}
}
