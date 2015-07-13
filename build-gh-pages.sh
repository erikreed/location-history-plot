#!/bin/bash
tmp=/tmp/location_parse

pub build

rm -rf $tmp
mkdir $tmp

cp -r .git $tmp
git -C $tmp checkout gh-pages
git -C $tmp reset --hard
rsync -av build/web/ $tmp
git -C $tmp add $tmp
git -C $tmp commit -m 'update gh-pages (auto)'
git -C $tmp push

rm -rf $tmp

