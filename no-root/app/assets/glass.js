/* XGuard optical glass. SDF / arc-lift lens math adapted from PrismalAGSL,
 * (c) 2026 Saurav Sajeev, MIT; see PRISMAL-LICENSE.txt.
 * Native browser backdrop filters sample live page content. Only small glass
 * controls receive a cached displacement map; normal cards use light CSS blur.
 */
(() => {
  'use strict';
  const root=document.documentElement, ns='http://www.w3.org/2000/svg';
  const reduce=matchMedia('(prefers-reduced-transparency: reduce)');
  const motion=matchMedia('(prefers-reduced-motion: reduce)');
  const blur=CSS.supports('backdrop-filter','blur(1px)')||CSS.supports('-webkit-backdrop-filter','blur(1px)');
  const optics=blur && /Chrome|Chromium|Edg\//.test(navigator.userAgent) && typeof SVGFEImageElement!=='undefined';
  const svg=document.createElementNS(ns,'svg');svg.setAttribute('width','0');svg.setAttribute('height','0');svg.setAttribute('aria-hidden','true');svg.classList.add('sprites');
  const defs=document.createElementNS(ns,'defs');svg.append(defs);document.body.append(svg);
  const cache=new Map();let scheduled=0, builds=0;
  function tag(name,attrs){const el=document.createElementNS(ns,name);for(const [k,v] of Object.entries(attrs))el.setAttribute(k,String(v));return el;}
  function mapImage(w,h,r){
    // Bounded texture size; created only on size changes, never per animation frame.
    const scale=Math.min(1,600/w,360/h),width=Math.max(1,Math.round(w*scale)),height=Math.max(1,Math.round(h*scale));
    const canvas=document.createElement('canvas');canvas.width=width;canvas.height=height;
    const ctx=canvas.getContext('2d'),image=ctx.createImageData(width,height),band=Math.min(15,r);
    for(let y=0;y<height;y++)for(let x=0;x<width;x++){
      const px=(x+.5)/scale-w/2,py=(y+.5)/scale-h/2;
      const qx=Math.abs(px)-(w/2-r),qy=Math.abs(py)-(h/2-r);
      const ox=Math.max(qx,0),oy=Math.max(qy,0),length=Math.hypot(ox,oy);
      const sd=length+Math.min(Math.max(qx,qy),0)-r;
      let dx=0,dy=0;
      if(sd<=0 && sd>-band){
        const a=Math.max(0,Math.min(1,1+sd/band)),lift=1-Math.sqrt(Math.max(0,1-a*a));
        const nx=length>0?Math.sign(px)*ox/length:(qx>=qy?Math.sign(px):0);
        const ny=length>0?Math.sign(py)*oy/length:(qy>qx?Math.sign(py):0);
        dx=nx*lift;dy=ny*lift;
      }
      const i=(y*width+x)*4;image.data[i]=Math.round(127.5+dx*118);image.data[i+1]=Math.round(127.5+dy*118);image.data[i+2]=128;image.data[i+3]=255;
    }
    ctx.putImageData(image,0,0);return canvas.toDataURL();
  }
  function setup(node){
    const r=node.getBoundingClientRect();if(!r.width||!r.height)return;
    const radius=Math.min(parseFloat(getComputedStyle(node).borderTopLeftRadius)||20,r.height/2,r.width/2);
    const key=[Math.round(r.width),Math.round(r.height),radius].join(':');const old=cache.get(node);
    if(old?.key===key)return;
    old?.filter.remove();const id='xg-optics-'+(++builds);
    const filter=tag('filter',{id,x:0,y:0,width:1,height:1,'color-interpolation-filters':'sRGB'});
    filter.append(tag('feImage',{href:mapImage(r.width,r.height,radius),width:'100%',height:'100%',preserveAspectRatio:'none',result:'lens'}));
    filter.append(tag('feDisplacementMap',{in:'SourceGraphic',in2:'lens',scale:12,xChannelSelector:'R',yChannelSelector:'G',result:'refracted'}));
    // Only a 0.12px channel difference at the strongest edge; no rainbow fill.
    filter.append(tag('feDisplacementMap',{in:'SourceGraphic',in2:'lens',scale:12.24,xChannelSelector:'R',yChannelSelector:'G',result:'redLens'}));
    filter.append(tag('feColorMatrix',{in:'redLens',type:'matrix',values:'1 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 1 0',result:'red'}));
    filter.append(tag('feColorMatrix',{in:'refracted',type:'matrix',values:'0 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0',result:'cyan'}));
    filter.append(tag('feBlend',{in:'red',in2:'cyan',mode:'screen'}));
    defs.append(filter);cache.set(node,{key,filter,id});
    node.style.backdropFilter='blur(var(--glass-blur)) saturate(1.03) url("#'+id+'")';
    node.style.webkitBackdropFilter=node.style.backdropFilter;
  }
  function sync(){
    scheduled=0;root.dataset.glassRenderer=reduce.matches||!blur?'solid':optics?'optical':'frosted';
    if(reduce.matches||!blur)return;
    if(optics)for(const node of document.querySelectorAll('.glass'))setup(node);
  }
  function schedule(){if(!scheduled&&!document.hidden)scheduled=requestAnimationFrame(sync);}
  const nav=document.querySelector('.bottom-nav');
  function syncNavigation(){
    const tabs=[...nav.querySelectorAll('button')];
    nav.style.setProperty('--tab-index',String(Math.max(0,tabs.findIndex(t=>t.getAttribute('aria-selected')==='true'))));
  }
  new MutationObserver(syncNavigation).observe(nav,{subtree:true,attributes:true,attributeFilter:['aria-selected']});
  const resize=window.ResizeObserver?new ResizeObserver(schedule):null;
  for(const el of document.querySelectorAll('.glass'))resize?.observe(el);
  document.addEventListener('toggle',schedule,true);addEventListener('resize',schedule,{passive:true});
  new MutationObserver(schedule).observe(document.body,{subtree:true,attributes:true,attributeFilter:['open']});
  reduce.addEventListener('change',schedule);
  document.addEventListener('visibilitychange',()=>{if(document.hidden){cancelAnimationFrame(scheduled);scheduled=0;}else schedule();});
  let lastHaptic=0;
  document.addEventListener('click',event=>{
    const button=event.target.closest('button,input[type=checkbox],select');
    if(!event.isTrusted||!button||button.disabled||performance.now()-lastHaptic<65)return;
    lastHaptic=performance.now();
    try{if(window.XGuard?.haptic)window.XGuard.haptic();else if(!motion.matches)navigator.vibrate?.(6);}catch{}
  },{capture:true,passive:true});
  window.XGuardGlass=Object.freeze({get info(){return {renderer:root.dataset.glassRenderer,maps:cache.size,builds,pendingFrame:Boolean(scheduled)};}});
  syncNavigation();sync();
})();
