(function(){
  var out=document.getElementById('probe');
  function fail(){out.textContent='Probe snapshot is not available yet. Close this panel and run ;kpm launch ghostguard-native again.';}
  try{
    var xhr=new XMLHttpRequest();
    xhr.open('GET','probe.txt?ts='+(new Date().getTime()),true);
    xhr.onreadystatechange=function(){
      if(xhr.readyState!==4)return;
      if((xhr.status>=200&&xhr.status<300)||xhr.status===0){
        out.textContent=xhr.responseText||'Probe returned an empty snapshot.';
      }else{fail();}
    };
    xhr.send(null);
  }catch(e){fail();}
})();
