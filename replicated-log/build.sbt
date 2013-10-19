name := "replicated-log"

scalaVersion := "2.10.3"

libraryDependencies ++= Seq(
  "org.scalaz"        %% "scalaz-core" % "7.0.4",
  "org.scalaz"        %% "scalaz-effect" % "7.0.4",
  "org.scalaz"        %% "scalaz-concurrent" % "7.0.4",
  "org.scalaz.stream" %% "scalaz-stream" % "0.1",
  "org.spire-math"    %% "spire"       % "0.6.0",
  "org.tpolecat"      %% "atto"        % "0.1",
  "org.scala-lang"    % "jline" % "2.10.3",
  "com.chuusai"       %  "shapeless_2.10.2" % "2.0.0-SNAPSHOT"
)

resolvers ++= Seq(
  "snapshots" at "http://oss.sonatype.org/content/repositories/snapshots",
  "tpolecat"  at "http://dl.bintray.com/tpolecat/maven",
  "releases"  at "http://oss.sonatype.org/content/repositories/releases"
)

initialCommands :=
  """import scalaz._
     import Scalaz._
     import atto._
     import Atto._"""
