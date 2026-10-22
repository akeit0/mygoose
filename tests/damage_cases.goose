import mygoose from "..";
import std;

fn covered(c: mygoose::Context&, r: mygoose::Rect) -> bool {
    for i in c.regions.rects.len {
        let part = mygoose::intersect(r, c.regions.rects[i]);
        if mygoose::same_rect(r, part) { return true; }
    } false
}
fn region_area_cases() {
    var regions = mygoose::DamageRegions {};
    assert(mygoose::damage_area(regions) == 0.0);
    mygoose::add_damage(regions, mygoose::Rect { 0.0, 4.0, 10.0, 2.0 });
    mygoose::add_damage(regions, mygoose::Rect { 4.0, 0.0, 2.0, 10.0 });
    assert(regions.rects.len == 2 && mygoose::damage_area(regions) == 36.0);
    assert(mygoose::rect_area(regions.bounds) == 100.0); // Overlap counts once; gaps count zero.
    mygoose::add_damage(regions, mygoose::Rect { 0.0, 4.0, 10.0, 2.0 });
    assert(mygoose::damage_area(regions) == 36.0); // Duplicate updates remain idempotent.
    mygoose::clear_damage(regions);
    assert(regions.rects.len == 0 && mygoose::rect_area(regions.bounds) == 0.0);
    mygoose::add_damage(regions, mygoose::Rect { 0.25, 1.5, 2.5, 3.0 });
    mygoose::add_damage(regions, mygoose::Rect { 10.25, 21.5, 2.5, 3.0 });
    assert(mygoose::damage_area(regions) == 15.0);
    // Compare the area sweep to an independent integer-pixel coverage oracle,
    // including the enlarged rectangles chosen when capacity is exceeded.
    for count in [1, 8, 16, 80] {
        mygoose::clear_damage(regions);
        for i in count { mygoose::add_damage(regions, mygoose::Rect { i * 13 % 50, i * 19 % 50, 7.0, 9.0 }); }
        var pixels: i32 = 0;
        for y in 64 { for x in 64 {
            var hit = false;
            for rect in regions.rects { if mygoose::contains(rect, x + 0.5, y + 0.5) { hit = true; break; } }
            if hit { pixels += 1; }
        } }
        assert(abs(mygoose::damage_area(regions) - pixels) < 0.01);
        assert(regions.rects.len <= mygoose::max_damage_regions);
    }
    print("PASS: independent bounded region geometry, exact overlap/fractional/overflow union area and raster oracle\n");
}
fn run_damage_cases(c: mygoose::Context&, cache: mygoose::SceneCache&) {
    region_area_cases();
    c = mygoose::Context { width: 400.0, height: 400.0 };
    let a = mygoose::Rect { 10.0, 20.0, 10.0, 10.0 };
    let b = mygoose::Rect { 350.0, 360.0, 10.0, 10.0 };
    mygoose::add_damage(c, a); mygoose::add_damage(c, b);
    assert(c.regions.rects.len == 2 && covered(c, a) && covered(c, b));
    mygoose::add_damage(c, mygoose::Rect { 12.0, 22.0, 2.0, 2.0 }); assert(c.regions.rects.len == 2);
    mygoose::add_damage(c, mygoose::Rect { -10.0, -10.0, 5.0, 5.0 }); assert(c.regions.rects.len == 2);
    // More changes than the fixed capacity must retain every damaged pixel.
    for i in 200 {
        mygoose::add_damage(c, mygoose::Rect { (i % 20) * 19.0, (i / 20) * 31.0, 3.25, 5.5 });
        assert(c.regions.rects.len <= 16);
    }
    assert(covered(c, a) && covered(c, b));
    for i in 200 { assert(covered(c, mygoose::Rect { (i % 20) * 19.0, (i / 20) * 31.0, 3.25, 5.5 })); }
    c = mygoose::Context { width: 400.0, height: 400.0 }; cache = mygoose::SceneCache {};
    c.count = 4;
    for i: i32 in c.count {
        c.nodes[i].rect = mygoose::Rect { 10.25 + i * 90.0, 20.75 + i * 80.0, 45.5, 50.25 };
        c.nodes[i].clip_rect = mygoose::Rect { w: 400.0, h: 400.0 };
        c.nodes[i].box.background = 0x22aacc; c.nodes[i].box.opaque = true; c.nodes[i].box.radius = 8.0;
    }
    c.nodes[2].box.shadow = mygoose::Shadow { blur: 5.0, x: 3.0, opacity: 0.3 };
    c.nodes[3].overlay = true;
    assert(mygoose::damage(c, cache)); assert(c.regions.rects.len == 1); mygoose::paint(c);
    for step in 30 {
        c.nodes[0].box.background = if step % 2 == 0 { 0xff3355 } else { 0x33ff55 };
        c.nodes[2].rect.x += if step % 2 == 0 { 7.25 } else { -7.25 };
        c.nodes[3].clip_rect.w = if step % 2 == 0 { 300.0 } else { 400.0 };
        assert(mygoose::damage(c, cache)); assert(c.regions.rects.len > 1);
        mygoose::paint(c); let partial = mygoose::mg_pixel_hash();
        c.force = true; assert(mygoose::damage(c, cache)); mygoose::paint(c);
        assert(partial == mygoose::mg_pixel_hash());
    }
    // Override an active sparse list, including an intervening changed node.
    c.nodes[0].box.background = 0xffffff; c.nodes[3].box.background = 0xffffff;
    assert(mygoose::damage(c, cache) && c.regions.rects.len > 1);
    c.nodes[1].box.background = 0xffaa11;
    c.dirty = mygoose::Rect { w: 400.0, h: 400.0 }; mygoose::paint(c); let override_hash = mygoose::mg_pixel_hash();
    c.force = true; assert(mygoose::damage(c, cache)); mygoose::paint(c); assert(override_hash == mygoose::mg_pixel_hash());
    c.count = 1; assert(mygoose::damage(c, cache)); mygoose::paint(c); let removed = mygoose::mg_pixel_hash();
    c.force = true; assert(mygoose::damage(c, cache)); mygoose::paint(c); assert(removed == mygoose::mg_pixel_hash());
    assert(!mygoose::damage(c, cache) && c.regions.rects.len == 0);
    // An explicit dirty rectangle must override the last scene damage list.
    c.dirty = mygoose::Rect { w: 400.0, h: 400.0 }; mygoose::paint(c); assert(removed == mygoose::mg_pixel_hash());
    // Adding damage after an explicit override must retain its bounding mode.
    c = mygoose::Context { width: 400.0, height: 400.0 };
    c.dirty = mygoose::Rect { 0.0, 0.0, 20.0, 20.0 };
    mygoose::add_damage(c, mygoose::Rect { 100.0, 100.0, 10.0, 10.0 });
    assert(mygoose::same_rect(c.dirty, mygoose::Rect { 0.0, 0.0, 110.0, 110.0 }));
    mygoose::add_damage(c, mygoose::Rect { -10.0, -10.0, 5.0, 5.0 });
    assert(mygoose::same_rect(c.dirty, mygoose::Rect { 0.0, 0.0, 110.0, 110.0 }));
    mygoose::paint(c); assert(c.paint_regions == 1 && mygoose::paint_area(c) == 12100.0);
    // Disjoint logical clips can still share a rounded physical boundary pixel.
    c = mygoose::Context { width: 400.0, height: 400.0 }; cache = mygoose::SceneCache {};
    c.count = 3;
    for i: i32 in c.count { c.nodes[i].clip_rect = mygoose::Rect { w: 400.0, h: 400.0 }; }
    c.nodes[0].rect = mygoose::Rect { w: 40.0, h: 40.0 };
    c.nodes[0].clip_rect.w = 10.25; c.nodes[0].box.background = 0xff1122;
    c.nodes[1].rect = mygoose::Rect { 10.3, 0.0, 4.0, 20.0 };
    c.nodes[2].rect = mygoose::Rect { 0.0, 300.0, 10.0, 10.0 };
    assert(mygoose::damage(c, cache)); mygoose::paint(c);
    c.nodes[1].value = 1.0; c.nodes[2].value = 1.0;
    assert(mygoose::damage(c, cache) && c.regions.rects.len == 2); mygoose::paint(c); let boundary = mygoose::mg_pixel_hash();
    c.force = true; assert(mygoose::damage(c, cache)); mygoose::paint(c); assert(boundary == mygoose::mg_pixel_hash());
    print("PASS: bounded damage regions retain coverage, distant gaps, fractional clips, moving shadows, overlays, removal and partial/full pixels\n");
}
