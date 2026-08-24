(function(){
  var probe=document.getElementById('probe');
  var watch=document.getElementById('watch');

  function loadInto(path, target, fallback){
    try{
      var xhr=new XMLHttpRequest();
      xhr.open('GET',path+'?ts='+(new Date().getTime()),true);
      xhr.onreadystatechange=function(){
        if(xhr.readyState!==4)return;
        if((xhr.status>=200&&xhr.status<300)||xhr.status===0){
          target.textContent=xhr.responseText||fallback;
        }else{
          target.textContent=fallback;
        }
      };
      xhr.send(null);
    }catch(e){
      target.textContent=fallback;
    }
  }

  function refresh(){
    loadInto('probe.txt',probe,'Probe snapshot is not available yet.');
    loadInto('watch.txt',watch,'Passive capture is running or no snapshot is available yet. Tap/swipe for about 12 seconds.');
  }

  refresh();
  var ticks=0;
  var timer=setInterval(function(){
    refresh();
    ticks+=1;
    if(ticks>=8)clearInterval(timer);
  },2000);
})();
